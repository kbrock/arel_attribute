# frozen_string_literal: true
require "arel"

# to work with ToSql, this needs to live in Arel::Nodes::*
# currently not patching ToSql and leveraging ToSql#Grouping implementation
class ::Arel::Nodes::ArelAttribute < Arel::Nodes::Grouping
  attr_accessor :name, :relation, :type

  def initialize(arel, name = nil, relation = nil, type = nil)
    super(arel)
    @name = name
    @relation = relation
    @type = type
  end

  # implement all methods defined in Arel::Nodes::Attribute
  # rubocop:disable Rails/Delegate
  # NOTE: PredicateBuilder#build build_bind_attribute directly calls relation.type()
  #       and not this method
  #       so the attribute type definition needs to be in the relation (typically model) for this to work
  def type_caster ; relation.type_for_attribute(name) ; end
  def lower ; relation.lower(self) ; end
  def type_cast_for_database(value) ; relation.type_cast_for_database(name, value) ; end
  def able_to_type_cast? ; relation.able_to_type_cast? ; end
  # rubocop:enable Rails/Delegate
end
