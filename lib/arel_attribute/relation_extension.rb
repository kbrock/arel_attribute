# frozen_string_literal: true

module ArelAttribute
  # Extends ActiveRecord::Relation to resolve arel attributes
  # registered via define_arel_attribute.
  #
  # Without this, order(:virtual_col) and select(:virtual_col) would treat
  # the symbol as a raw column name instead of routing through TableProxy.
  module RelationExtension
    # For SELECT and PLUCK, arel attributes need an AS alias so the result column
    # is accessible by name (e.g. result.doubled instead of result["(col + col)"]).
    # This must remain public to match Rails' visibility (called on explicit receiver in pluck).
    def arel_columns(columns)
      super.map do |col|
        if col.is_a?(Arel::Nodes::ArelAttribute) && col.name
          col.as(col.name)
        else
          col
        end
      end
    end

    private

    def build_select(arel)
      super

      # When DISTINCT is used with ORDER BY on virtual arel attributes,
      # PG/MySQL require the ORDER BY expressions to appear in the SELECT list.
      if distinct_value
        selected_names = select_values.map { |v| v.is_a?(Symbol) ? v.to_s : (v.is_a?(String) ? v : nil) }.compact.to_set
        order_values.each do |o|
          expr = o.is_a?(Arel::Nodes::Ordering) ? o.expr : o
          if expr.is_a?(Arel::Nodes::ArelAttribute) && expr.name && !selected_names.include?(expr.name)
            arel.project(expr.as(expr.name))
          end
        end
      end
    end

    # query_methods.rb#arel_column
    # Resolve arel attribute names to their arel expressions.
    # Used by both select() and order() via arel_columns/order_column.
    def arel_column(field)
      attr_name = field.is_a?(Symbol) ? field.name : field
      attr_name = model.attribute_aliases[attr_name] || attr_name

      if model.respond_to?(:arel_attribute?) && model.arel_attribute?(attr_name)
        table[attr_name]
      else
        super
      end
    end
  end
end

ActiveRecord::Relation.prepend(ArelAttribute::RelationExtension)
