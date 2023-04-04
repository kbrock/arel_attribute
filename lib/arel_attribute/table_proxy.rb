# frozen_string_literal: true
require "arel"
module ArelAttribute
  class TableProxy < Arel::Table
    def [](name, table = self)
      # think alias resolution is needed for counts
      if (col_alias = @klass.attribute_alias(name))
        name = col_alias
      end
      @klass.arel_attribute(name, table) || super
    end
  end
end
