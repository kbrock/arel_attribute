# frozen_string_literal: true

require "arel"

# Arel node that wraps a SQL expression and carries type information.
#
# Extends Grouping so it renders as (expression) in SQL via the existing
# ToSql visitor — no visitor patching needed.
#
# Implements the interface expected by ActiveRecord's PredicateBuilder
# (type_caster, type_cast_for_database, able_to_type_cast?) so that
# values in WHERE clauses are properly cast.
class Arel::Nodes::ArelAttribute < Arel::Nodes::Grouping
  attr_accessor :name, :relation, :type

  def initialize(arel, name = nil, relation = nil, type = nil)
    super(arel)
    @name = name
    @relation = relation
    @type = type
  end

  def type_caster
    relation.type_for_attribute(name)
  end

  def lower
    relation.lower(self)
  end

  def type_cast_for_database(value)
    relation.type_cast_for_database(name, value)
  end

  def able_to_type_cast?
    relation.able_to_type_cast?
  end
end
