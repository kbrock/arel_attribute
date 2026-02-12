# frozen_string_literal: true

module ArelAttribute
  # Extends ActiveRecord associations to support arity-2 scope lambdas
  # for custom join conditions (e.g. LIKE-based ancestry queries).
  #
  # Structured as two separable patches, each targeting Rails core (main/9.0)
  # and applied today as monkey-patches on 8.x/7.2.
  #
  # Patch1: Allow arity-2 scope lambdas to eager load. FK=PK still fires alongside
  #         the lambda. Independently useful; proposable to Rails core on its own.
  #
  # Patch2: Add match: option to suppress FK=PK and replace Ruby-side bucketing
  #         with a custom lambda. match: and FK=PK suppression are one atomic change.
  #
  # Prepend chain on HasManyReflection + BelongsToReflection (outermost first):
  #   Patch2::ReflectionExtension -> Patch1::ReflectionExtension -> Rails
  #
  # NOTE: When debugging, always write tests rather than ad-hoc ruby -e scripts.
  # The test environment sets up models correctly; standalone scripts often fail.
  module MatchAssociation
    module Patch1
      module ReflectionExtension
        # Override: ActiveRecord::Reflection::AbstractReflection#check_eager_loadable!
        # Source: activerecord 7.2.3 lib/active_record/reflection.rb:194
        # Also:   activerecord 8.1.2 lib/active_record/reflection.rb:194
        #
        # Allow arity-2 scope lambdas to be eager-loaded (joins/includes).
        # Rails normally rejects any scope with arity != 0.
        def check_eager_loadable!
          # CHANGED: allow arity-2 scopes through without raising
          return if scope&.arity == 2
          # /CHANGED

          super
        end

        # Override: ActiveRecord::Reflection::AbstractReflection#join_scope
        # Source: activerecord 7.2.3 lib/active_record/reflection.rb:200
        # Also:   activerecord 8.1.2 lib/active_record/reflection.rb:200
        #
        # When scope arity is 2, call super (which adds FK=PK), then merge the
        # arity-2 lambda result on top. FK=PK still fires — this alone is not
        # sufficient for ancestry (both FK=PK and LIKE fire). Patch2 fixes that.
        def join_scope(table, foreign_table, foreign_klass)
          # CHANGED: for arity-2 scopes, call super first (FK=PK added), then merge lambda
          return super unless scope&.arity == 2
          # /CHANGED

          base = super

          # CHANGED: build predicate_builder compatible with Rails 7.2 and 8.x
          # Rails 7.2 compatibility: predicate_builder(table) is a private method on AbstractReflection
          # Rails 8.x: klass.predicate_builder.with(TableMetadata)
          pb = if respond_to?(:predicate_builder, true)
                 predicate_builder(table)
               else
                 klass.predicate_builder.with(ActiveRecord::TableMetadata.new(klass, table))
               end
          klass_scope = klass_join_scope(table, pb)
          # /CHANGED

          scope_relation = klass_scope.instance_exec(foreign_table, table, &scope) || klass_scope
          base.merge!(scope_relation)
        end
      end
    end

    module Patch2
      module ReflectionExtension
        # Override: ActiveRecord::Reflection::AbstractReflection#join_scope
        # Source: activerecord 7.2.3 lib/active_record/reflection.rb:200
        # Also:   activerecord 8.1.2 lib/active_record/reflection.rb:200
        #
        # When match: is present and scope arity is 2, call the lambda directly
        # without calling super — suppresses FK=PK. Developer's lambda owns the
        # full join condition. Otherwise chains to Patch1 -> Rails.
        def join_scope(table, foreign_table, foreign_klass)
          # CHANGED: when match: present, skip FK=PK entirely; lambda owns join condition
          return super unless options[:match] && scope&.arity == 2
          # /CHANGED

          # CHANGED: build predicate_builder compatible with Rails 7.2 and 8.x
          # Rails 7.2 compatibility: predicate_builder(table) is a private method on AbstractReflection
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

          # CHANGED: call arity-2 scope directly; do NOT call super (FK=PK suppressed)
          # original (via Patch1 super): base = super; base.merge!(scope_relation)
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
          # CHANGED: skip standard FK = value when match: is present
          # Arity-2 scope handles its own WHERE; FK=value would override the LIKE WHERE.
          # original: add_constraints(scope, owner, reflection)
          # RuntimeReflection does not delegate options; unwrap to underlying reflection
          refl = reflection.respond_to?(:options) ? reflection : reflection.instance_variable_get(:@reflection)
          return scope if refl&.options&.dig(:match)
          # /CHANGED

          super
        end
      end

      # Loader query that calls the arity-2 scope's array branch instead of
      # the standard WHERE fk IN (...) for associations with match: present.
      #
      # Replaces: ActiveRecord::Associations::Preloader::Association::LoaderQuery
      # Source: activerecord 7.2.3 lib/active_record/associations/preloader/association.rb:22
      # Also:   activerecord 8.1.2 lib/active_record/associations/preloader/association.rb:22
      #
      # This logic belongs in Rails' LoaderQuery eventually; it lives as a
      # separate class here to keep the diff minimal.
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
        # call the arity-2 scope with the owners array (array branch of lambda).
        # original: scope.where(association_key_name => keys).load(&block)
        def load_records_for_keys(owners_for_query, &block)
          return [] if owners_for_query.empty?

          base_scope = @scope.klass.scope_for_association
          relation = base_scope.instance_exec(owners_for_query, nil, &@reflection.scope) || base_scope
          relation.load(&block)
        end
        # /CHANGED
      end

      # Override: ActiveRecord::Associations::Preloader::Association#loader_query + #load_records
      # Source: activerecord 7.2.3 lib/active_record/associations/preloader/association.rb:170
      # Also:   activerecord 8.1.2 lib/active_record/associations/preloader/association.rb:170
      module PreloaderAssociationExtension
        def loader_query
          # CHANGED: use MatchLoaderQuery when match: is present
          # original: LoaderQuery.new(scope, association_key_name)
          if reflection.options[:match]
            MatchLoaderQuery.new(scope, association_key_name, reflection, send(:owners))
          else
            super
          end
          # /CHANGED
        end

        def load_records(raw_records = nil)
          return super unless reflection.options[:match]

          match = reflection.options[:match]
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
      # Source: activerecord 7.2.3 lib/active_record/associations/association.rb:72
      # Also:   activerecord 8.1.2 lib/active_record/associations/association.rb:72
      #
      # Arity-2 scopes with match: build the WHERE clause from owner state, so the
      # cached @association_scope becomes stale when the owner changes.
      module AssociationExtension
        def reset
          # CHANGED: also clear @association_scope when match: is present
          super.tap { reset_scope if reflection.options[:match] }
          # /CHANGED
        end
      end

      # Override: ActiveRecord::Associations::Builder::HasMany (singleton)
      # Adds :match to valid_options and validates it requires an arity-2 scope.
      module HasManyBuilderExtension
        def valid_options(options)
          # CHANGED: allow :match option on has_many
          super + [:match]
          # /CHANGED
        end
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  # Patch1 (innermost): allow arity-2 scope lambdas to eager load; FK=PK still fires
  ActiveRecord::Reflection::HasManyReflection.prepend(ArelAttribute::MatchAssociation::Patch1::ReflectionExtension)
  ActiveRecord::Reflection::BelongsToReflection.prepend(ArelAttribute::MatchAssociation::Patch1::ReflectionExtension)

  # Patch2 (outermost — super chains to Patch1): match: suppresses FK=PK and uses custom bucketing
  ActiveRecord::Reflection::HasManyReflection.prepend(ArelAttribute::MatchAssociation::Patch2::ReflectionExtension)
  ActiveRecord::Reflection::BelongsToReflection.prepend(ArelAttribute::MatchAssociation::Patch2::ReflectionExtension)
  ActiveRecord::Associations::AssociationScope.prepend(ArelAttribute::MatchAssociation::Patch2::AssociationScopeExtension)
  ActiveRecord::Associations::Preloader::Association.prepend(ArelAttribute::MatchAssociation::Patch2::PreloaderAssociationExtension)
  ActiveRecord::Associations::Association.prepend(ArelAttribute::MatchAssociation::Patch2::AssociationExtension)
  ActiveRecord::Associations::Builder::HasMany.singleton_class.prepend(ArelAttribute::MatchAssociation::Patch2::HasManyBuilderExtension)
end
