# frozen_string_literal: true

module ArelAttribute
  # Extends ActiveRecord associations to support arity-2 scope lambdas
  # for custom join conditions (e.g. LIKE-based ancestry queries).
  #
  # The scope block takes (table, foreign_table) for joins,
  # or (owner) / ([owners]) for single-record/preload access.
  # The FK/PK handle Rails bucketing.
  #
  # NOTE: When debugging, always write tests rather than ad-hoc ruby -e scripts.
  # The test environment sets up models correctly; standalone scripts often fail.
  module MatchAssociation
    module ReflectionExtension
      # Override: ActiveRecord::Reflection::AbstractReflection#check_eager_loadable!
      # Source: activerecord 7.2.3 lib/active_record/reflection.rb:194
      # Also:   activerecord 8.1.2 lib/active_record/reflection.rb:194
      #
      # Allow arity-2 scope lambdas to be eager-loaded (joins/includes).
      # Rails normally rejects any scope with arity != 0.
      def check_eager_loadable!
        # CHANGED: allow arity-2 scopes through without raising
        # original: (no early return — always raised for arity != 0)
        return if scope&.arity == 2
        # /CHANGED

        super
      end

      # Override: ActiveRecord::Reflection::AbstractReflection#join_scope
      # Source: activerecord 7.2.3 lib/active_record/reflection.rb:200
      # Also:   activerecord 8.1.2 lib/active_record/reflection.rb:200
      def join_scope(table, foreign_table, foreign_klass)
        # CHANGED: skip standard join_scope for arity-2 scopes; handle below
        # original: (no early return — always built FK=PK join)
        return super unless scope&.arity == 2
        # /CHANGED

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
        if type
          klass_scope.where!(type => foreign_klass.polymorphic_name)
        end

        # CHANGED: call arity-2 scope with (owner, target) instead of join_scopes + FK=PK
        # original: scope_chain_items = join_scopes(table, predicate_builder)
        #           scope_chain_items.inject(klass_scope, &:merge!)
        #           klass_scope.where!(table[join_primary_key].eq(foreign_table[join_foreign_key]))
        scope_relation = klass_scope.instance_exec(foreign_table, table, &scope) || klass_scope
        # /CHANGED
        klass_scope = scope_relation

        if klass.finder_needs_type_condition?
          klass_scope.where!(klass.send(:type_condition, table))
        end

        klass_scope
      end
    end

    # Override: ActiveRecord::Associations::AssociationScope (private methods)
    # Source: activerecord 7.2.3 lib/active_record/associations/association_scope.rb:53
    # Also:   activerecord 8.1.2 lib/active_record/associations/association_scope.rb:53
    module AssociationScopeExtension
      private

      def last_chain_scope(scope, reflection, owner)
        # CHANGED: skip standard FK = value for arity-2 scopes
        # Arity-2 scopes handle their own WHERE via eval_scope (called with owner).
        # original: add_constraints(scope, owner, reflection)
        return scope if reflection.scope&.arity == 2
        # /CHANGED

        super
      end
    end

    # Loader query that skips the standard WHERE fk IN (...) for arity-2 scopes.
    # Instead, calls the scope with all owners as an array to build a batched query.
    #
    # Replaces: ActiveRecord::Associations::Preloader::Association::LoaderQuery
    # Source: activerecord 7.2.3 lib/active_record/associations/preloader/association.rb:22
    # Also:   activerecord 8.1.2 lib/active_record/associations/preloader/association.rb:22
    class Arity2LoaderQuery
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
      # call the arity-2 scope with the owners array.
      # original: scope.where(association_key_name => keys).load(&block)
      def load_records_for_keys(owners_for_query, &block)
        return [] if owners_for_query.empty?

        base_scope = @scope.klass.scope_for_association
        relation = base_scope.instance_exec(owners_for_query, nil, &@reflection.scope) || base_scope
        relation.load(&block)
      end
      # /CHANGED
    end

    # Override: ActiveRecord::Associations::Preloader::Association#loader_query
    # Source: activerecord 7.2.3 lib/active_record/associations/preloader/association.rb:170
    # Also:   activerecord 8.1.2 lib/active_record/associations/preloader/association.rb:170
    module PreloaderAssociationExtension
      def loader_query
        # CHANGED: use Arity2LoaderQuery for arity-2 scopes
        # original: LoaderQuery.new(scope, association_key_name)
        if reflection.scope&.arity == 2
          Arity2LoaderQuery.new(scope, association_key_name, reflection, send(:owners))
        else
          super
        end
        # / CHANGED
      end
    end

    # Override: ActiveRecord::Associations::Association#reset
    # Source: activerecord 7.2.3 lib/active_record/associations/association.rb:72
    # Also:   activerecord 8.1.2 lib/active_record/associations/association.rb:72
    #
    # Arity-2 scopes build the WHERE clause from owner state, so the
    # cached @association_scope becomes stale when the owner changes.
    # Standard associations don't need this because their scope is
    # generic and reads FK values fresh at query time.
    #
    # NOTE: This is aggressive — it clears scope on every reset.
    # For some associations (e.g. descendants) the DB-consistent scope
    # may be preferred over a rebuilt scope using unsaved owner state.
    # Investigate whether this should be opt-in per association.
    module AssociationExtension
      def reset
        # CHANGED: also clear @association_scope for arity-2 scopes
        # original: (only clears @loaded and @target, NOT @association_scope)
        super.tap { reset_scope if reflection.scope&.arity == 2 }
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
end
