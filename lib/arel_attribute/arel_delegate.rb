# frozen_string_literal: true

module ArelAttribute
  module ArelDelegate
    # Build a correlated subquery that selects `col` from the target of `to_ref`.
    #
    # Only works for belongs_to and has_one — these return a single row.
    # For has_one, LIMIT 1 is added to the subquery.
    #
    # @param col [String, Symbol] column name on the target model
    # @param to_ref [ActiveRecord::Reflection] the association reflection
    # @return [Proc, nil] arel lambda or nil if the association can't be represented in SQL
    def self.virtual_delegate_arel(owner_class, col, to_ref)
      return unless to_ref && [:has_one, :belongs_to].include?(to_ref.macro)

      lambda do |t|
        src_model_id = owner_class.arel_table[to_ref.join_foreign_key, t]
        blk = ->(arel) { arel.limit = 1 } if to_ref.macro == :has_one
        select_from_alias(to_ref, col, to_ref.join_primary_key, src_model_id, &blk)
      end
    end

    # Build correlated subquery SQL:
    #   (SELECT target.col FROM target WHERE target.join_key = source.fk)
    #
    # Handles self-joins by aliasing the target table.
    # Handles polymorphic associations by adding a type constraint.
    # Applies association scopes (e.g. has_one with ordering).
    #
    # Based on ActiveRecord AssociationScope.scope
    def self.select_from_alias(to_ref, col, to_model_col_name, src_model_id)
      query = if to_ref.scope
        to_ref.klass.instance_exec(nil, &to_ref.scope)
      else
        to_ref.klass.all
      end

      to_table = select_from_alias_table(to_ref.klass, src_model_id.relation)
      to_model_id = to_ref.klass.arel_table[to_model_col_name, to_table]
      to_column = to_ref.klass.arel_table[col, to_table]
      arel = query.except(:select).select(to_column).arel
        .from(to_table)
        .where(to_model_id.eq(src_model_id))

      if to_ref.type
        polymorphic_type = to_ref.active_record.base_class.name
        arel = arel.where(to_ref.klass.arel_table[to_ref.type].eq(polymorphic_type))
      end

      yield arel if block_given?

      arel
    end

    # For self-joins, alias the target table to avoid ambiguity.
    def self.select_from_alias_table(to_klass, src_relation)
      to_table = to_klass.arel_table
      if to_table.name == src_relation.name
        to_table = to_table.alias("#{to_table.name}_sub")
      end
      to_table
    end
  end
end
