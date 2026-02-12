# frozen_string_literal: true

module ArelAttribute
  # Extends ActiveRecord associations to support a join_strategy: option
  # for custom join conditions (e.g. LIKE-based ancestry queries).
  #
  # join_strategy: accepts a Module implementing 4 methods:
  #   join_arel(owner_table, foreign_table)  — JOIN context (both arel tables)
  #   where_record(owner, foreign_table)     — single record WHERE
  #   join_records(owners, foreign_table)    — preload batch
  #   match?(record, owner)                  — Ruby-side preload bucketing
  #
  # Methods are called via instance_exec on the relation (self = relation),
  # except match? which is called as a plain method.
  # Use define_method closures to capture outer-scope locals.
  #
  # NOTE: When debugging, always write tests rather than ad-hoc ruby -e scripts.
  # The test environment sets up models correctly; standalone scripts often fail.
  module MatchAssociation
    def self.resolve_join_strategy(reflection)
      strategy = reflection.options[:join_strategy]
      case strategy
      when Module then strategy
      when Symbol then Object.const_get(strategy.to_s)
      when String then Object.const_get(strategy)
      else raise ArgumentError, "join_strategy: must be a Module, Symbol, or String"
      end
    end

    module ReflectionExtension
      # Override: ActiveRecord::Reflection::AbstractReflection#check_eager_loadable!
      # Source: activerecord 8.1.2 lib/active_record/reflection.rb:194
      #
      # Allow join_strategy: associations to be eager-loaded (joins/includes).
      # Rails normally rejects any scope with arity != 0.
      def check_eager_loadable!
        # CHANGED: allow join_strategy: associations through without raising
        return if options[:join_strategy]
        # /CHANGED

        super
      end

      # Override: ActiveRecord::Reflection::AbstractReflection#join_scope
      # Source: activerecord 8.1.2 lib/active_record/reflection.rb:200
      #
      # When join_strategy: is set, call strategy#join_arel directly without
      # calling super — suppresses FK=PK. The strategy fully owns the join condition.
      def join_scope(table, foreign_table, foreign_klass)
        # CHANGED: for join_strategy: associations, skip FK=PK entirely; strategy owns join condition
        return super unless options[:join_strategy]
        # /CHANGED

        strategy = ArelAttribute::MatchAssociation.resolve_join_strategy(self)

        # CHANGED: build predicate_builder compatible with Rails 7.2 and 8.x
        # Rails 7.2: predicate_builder(table) is a private method on AbstractReflection
        # Rails 8.x: klass.predicate_builder.with(TableMetadata)
        pb = if respond_to?(:predicate_builder, true)
               predicate_builder(table)
             else
               klass.predicate_builder.with(ActiveRecord::TableMetadata.new(klass, table))
             end
        klass_scope = klass_join_scope(table, pb)
        # /CHANGED

        klass_scope.where!(type => foreign_klass.polymorphic_name) if type

        # CHANGED: call strategy#join_arel via instance_exec; strategy owns join condition
        # foreign_table = owner's table; table = target's table (klass's arel_table alias)
        klass_scope = klass_scope.extend(strategy).instance_exec(foreign_table, table) do |ft, t|
          join_arel(ft, t)
        end || klass_scope
        # /CHANGED

        klass_scope.where!(klass.send(:type_condition, table)) if klass.finder_needs_type_condition?

        klass_scope
      end
    end

    # Override: ActiveRecord::Associations::AssociationScope (private methods)
    # Source: activerecord 8.1.2 lib/active_record/associations/association_scope.rb:53
    module AssociationScopeExtension
      private

      def last_chain_scope(scope, reflection, owner)
        # CHANGED: skip standard FK = value when join_strategy: is set
        # Strategy handles its own WHERE via where_record; FK=value would override it.
        # RuntimeReflection does not expose options directly; unwrap to underlying reflection.
        refl = reflection.respond_to?(:options) ? reflection : reflection.instance_variable_get(:@reflection)
        if refl&.options&.[](:join_strategy)
          strategy = ArelAttribute::MatchAssociation.resolve_join_strategy(refl)
          foreign_table = reflection.aliased_table
          return scope.extend(strategy).instance_exec(owner, foreign_table) do |o, ft|
            where_record(o, ft)
          end || scope
        end
        # /CHANGED

        super
      end
    end

    # Loader query that calls the strategy's join_records method instead of
    # the standard WHERE fk IN (...) for associations with join_strategy:.
    #
    # Replaces: ActiveRecord::Associations::Preloader::Association::LoaderQuery
    # Source: activerecord 8.1.2 lib/active_record/associations/preloader/association.rb:22
    class MatchLoaderQuery
      attr_reader :scope, :association_key_name

      def initialize(scope, association_key_name, reflection, owners)
        @scope = scope
        @association_key_name = association_key_name
        @reflection = reflection
        @owners = owners
      end

      def eql?(other)
        other.is_a?(self.class) &&
          association_key_name == other.association_key_name &&
          scope.table_name == other.scope.table_name
      end

      def hash
        [self.class, association_key_name, scope.table_name].hash
      end

      def records_for(loaders)
        all_owners = loaders.flat_map { |l| l.send(:owners) }.uniq(&:__id__)
        load_records_for_keys(all_owners)
      end

      def load_records_in_batch(loaders)
        raw_records = records_for(loaders)
        loaders.each do |loader|
          loader.load_records(raw_records)
          loader.run
        end
      end

      # CHANGED: instead of scope.where(association_key_name => keys),
      # call strategy#join_records with the owners array.
      def load_records_for_keys(owners_for_query, &block)
        return [] if owners_for_query.empty?

        base_scope = @scope.klass.scope_for_association
        strategy = ArelAttribute::MatchAssociation.resolve_join_strategy(@reflection)
        relation = base_scope.extend(strategy).instance_exec(owners_for_query, base_scope.klass.arel_table) do |owners, ft|
          join_records(owners, ft)
        end || base_scope
        relation.load(&block)
      end
      # /CHANGED
    end

    # Override: ActiveRecord::Associations::Preloader::Association#loader_query + #load_records
    # Source: activerecord 8.1.2 lib/active_record/associations/preloader/association.rb:170
    module PreloaderAssociationExtension
      def loader_query
        # CHANGED: use MatchLoaderQuery when join_strategy: is set
        # original: LoaderQuery.new(scope, association_key_name)
        if reflection.options[:join_strategy]
          MatchLoaderQuery.new(scope, association_key_name, reflection, send(:owners))
        else
          super
        end
        # /CHANGED
      end

      def load_records(raw_records = nil)
        return super unless reflection.options[:join_strategy]

        strategy = ArelAttribute::MatchAssociation.resolve_join_strategy(reflection)
        # match? is an instance method defined via define_method; bind to a plain object
        match_method = strategy.instance_method(:match?)
        match = ->(record, owner) { match_method.bind_call(Object.new, record, owner) }
        @records_by_owner = {}.compare_by_identity
        raw_records ||= loader_query.records_for([self])
        # SQL array branch returns one row per (record, owner) match; dedup by id
        # before match: iterates all owners so each record is only bucketed once.
        raw_records = raw_records.uniq(&:id)
        @preloaded_records = raw_records.select do |record|
          assignments = false

          # CHANGED: replace owners_by_key[derive_key(record, association_key_name)]
          # original: owners_by_key[derive_key(record, association_key_name)]&.each do |owner|
          send(:owners).select { |owner| match.call(record, owner) }.each do |owner|
            # /CHANGED
            entries = (@records_by_owner[owner] ||= [])

            if reflection.collection? || entries.empty?
              entries << record
              assignments = true
            end
          end

          assignments
        end
      end
    end

    # Override: ActiveRecord::Associations::Association#reset
    # Source: activerecord 8.1.2 lib/active_record/associations/association.rb:72
    #
    # join_strategy: associations build the WHERE clause from owner state, so the
    # cached @association_scope becomes stale when the owner changes.
    module AssociationExtension
      def reset
        # CHANGED: also clear @association_scope when join_strategy: is set
        super.tap { reset_scope if reflection.options[:join_strategy] }
        # /CHANGED
      end
    end

    # Override: ActiveRecord::Associations::Builder::HasMany (singleton)
    # Adds :join_strategy to valid_options.
    module HasManyBuilderExtension
      def valid_options(options)
        # CHANGED: allow :join_strategy option on has_many
        super + [:join_strategy]
        # /CHANGED
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Reflection::HasManyReflection.prepend(ArelAttribute::MatchAssociation::ReflectionExtension)
  ActiveRecord::Reflection::BelongsToReflection.prepend(ArelAttribute::MatchAssociation::ReflectionExtension)
  ActiveRecord::Associations::AssociationScope.prepend(ArelAttribute::MatchAssociation::AssociationScopeExtension)
  ActiveRecord::Associations::Preloader::Association.prepend(ArelAttribute::MatchAssociation::PreloaderAssociationExtension)
  ActiveRecord::Associations::Association.prepend(ArelAttribute::MatchAssociation::AssociationExtension)
  ActiveRecord::Associations::Builder::HasMany.singleton_class.prepend(ArelAttribute::MatchAssociation::HasManyBuilderExtension)
end
