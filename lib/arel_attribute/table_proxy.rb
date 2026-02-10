# frozen_string_literal: true

require "arel"

module ArelAttribute
  # TableProxy intercepts arel_table[:name] lookups to return arel expressions
  # for attributes registered via define_arel_attribute.
  #
  # For real columns, it falls through to the standard Arel::Table behavior.
  class TableProxy < Arel::Table
    def [](name, table = self)
      if (col_alias = @klass.attribute_alias(name))
        name = col_alias
      end

      arel_block = @klass.arel_aliases[name.to_s]
      if arel_block
        Arel::Nodes::ArelAttribute.new(arel_block[table], name.to_s, table)
      elsif table == self
        super(name)
      else
        # Called from TableAlias#[] with table=alias. Create the attribute
        # referencing the alias so self-joins use the correct table name.
        Arel::Attributes::Attribute.new(table, name)
      end
    end

    def alias(name)
      ArelAttribute::AliasedTableProxy.new(self, name, @klass)
    end
  end

  # AliasedTableProxy preserves arel attribute lookups on aliased tables.
  #
  # When Rails creates a self-join, it aliases the table (e.g. "people_sub").
  # Without this, table_alias[:virtual_col] would return a plain Arel::Attribute,
  # losing the arel expression. This ensures the interception still works.
  class AliasedTableProxy < Arel::Nodes::TableAlias
    def initialize(table, name, klass)
      super(table, name)
      @klass = klass
    end

    def [](name)
      arel_block = @klass.arel_aliases[name.to_s]
      if arel_block
        Arel::Nodes::ArelAttribute.new(arel_block[self], name.to_s, self)
      else
        super
      end
    end
  end
end
