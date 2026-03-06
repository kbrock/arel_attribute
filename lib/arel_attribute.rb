# frozen_string_literal: true

require "active_support/concern"
require "active_record"
require "arel"

require "arel/nodes/arel_attribute"
require "arel_attribute/version"
require "arel_attribute/table_proxy"
require "arel_attribute/relation_extension"
require "arel_attribute/arel_aggregate"
require "arel_attribute/sql_detection"

module ArelAttribute
  class Error < StandardError; end

  module Base
    def self.included(base)
      base.extend ClassMethods
      base.include InstanceMethods
      # base.include ArelAttribute::ArelAggregate
      # name => arel_block (lambda that takes an arel table, returns an arel node)
      base.class_attribute :arel_aliases, instance_accessor: false, default: {}
      # name => type (symbol like :integer, or an ActiveModel::Type instance)
      base.class_attribute :arel_attribute_types, instance_accessor: false, default: {}
    end

    module InstanceMethods
      # Rails internals (associations, preloading) read FK/PK values via
      # _read_attribute, not via the public method. For virtual-only arel
      # attributes (not backed by a real column), fall back to calling the
      # Ruby getter so belongs_to/has_many with virtual FKs work.
      def _read_attribute(attr_name, &block) # :nodoc:
        if self.class.arel_attribute?(attr_name) && !self.class.column_names.include?(attr_name.to_s)
          written = @arel_attribute_values&.dig(attr_name.to_s)
          return written unless written.nil?
          # Only call the ruby getter if the method is explicitly defined
          # (not an AR-generated attribute method, which would recurse back here).
          if self.class.method_defined?(attr_name, false) ||
             self.class.private_method_defined?(attr_name, false)
            return send(attr_name)
          end
        end
        super
      end

      # Rails associations call _write_attribute to set FK values on
      # child records. For virtual-only arel attributes, store the value
      # in-memory so the getter and belongs_to can resolve the parent.
      def _write_attribute(attr_name, value) # :nodoc:
        if self.class.arel_attribute?(attr_name) && !self.class.column_names.include?(attr_name.to_s)
          @arel_attribute_values ||= {}
          @arel_attribute_values[attr_name.to_s] = value
        else
          super
        end
      end
    end

    module ClassMethods
      # Define an attribute backed by an arel expression.
      #
      # The block receives the arel table and returns an arel node.
      # This allows the attribute to be used in WHERE, ORDER BY, and SELECT clauses.
      #
      #   arel_attribute :parent_id, :integer do |t|
      #     Arel::Nodes::NamedFunction.new('SUBSTR', [t[:path], ...])
      #   end
      #
      def arel_attribute(name, type, &block)
        raise ArgumentError, "arel block is required for arel_attribute" unless block
        self.arel_aliases = arel_aliases.merge(name.to_s => block)
        self.arel_attribute_types = arel_attribute_types.merge(name.to_s => type)
      end

      def arel_attribute_names
        arel_aliases.keys
      end

      def arel_attribute?(name)
        arel_aliases.key?(name.to_s)
      end

      def attribute_supported_by_sql?(name)
        column_names.include?(name.to_s) || arel_attribute?(name)
      end

      # Override: ActiveModel::AttributeRegistration::ClassMethods#type_for_attribute
      # Source: activemodel 8.1.2 lib/active_model/attribute_registration.rb:43
      #
      # Returns the correct type for virtual arel attributes. This is used by
      # the preloader to type-cast FK values in WHERE clauses
      # (e.g. WHERE parent_id IN (1, 2) needs integer binding).
      #
      # We cannot use _default_attributes or attribute_types for this because:
      # - _default_attributes makes Rails expect the column in DB result sets
      #   (causes MissingAttributeError on load)
      # - attribute_types mutations are lost when @attribute_types is reset
      #   (e.g. reload_schema_from_cache calls reset_default_attributes!)
      def type_for_attribute(attr_name, &block)
        name = attr_name.to_s
        if arel_attribute_types.key?(name)
          resolved_arel_attribute_types[name]
        else
          super
        end
      end

      def arel_table
        @arel_table ||= ArelAttribute::TableProxy.new(table_name, klass: self)
      end

      private

      # Lazily resolve symbolic type names (e.g. :integer) to actual type objects.
      # Cached per class; reset if arel_attribute_types changes (class_attribute handles this).
      def resolved_arel_attribute_types
        @resolved_arel_attribute_types ||= arel_attribute_types.transform_values do |type|
          if type.is_a?(Symbol) || type.is_a?(String)
            ActiveRecord::Type.lookup(type, adapter: ActiveRecord::Type.adapter_name_from(self))
          else
            type
          end
        end
      end
    end
  end
end
