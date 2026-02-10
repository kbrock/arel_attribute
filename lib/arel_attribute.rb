# frozen_string_literal: true

require "active_support/concern"
require "active_record"
require "arel"

require "arel/nodes/arel_attribute"
require "arel_attribute/version"
require "arel_attribute/table_proxy"
require "arel_attribute/relation_extension"
require "arel_attribute/virtual_total"
require "arel_attribute/sql_detection"

module ArelAttribute
  class Error < StandardError; end

  module Base
    def self.included(base)
      base.extend ClassMethods
      base.include InstanceMethods
#      base.include ArelAttribute::VirtualTotal
      # name => arel_block (lambda that takes an arel table, returns an arel node)
      base.class_attribute :arel_aliases, instance_accessor: false, default: {}
      # name => type (symbol like :integer, or an ActiveModel::Type instance)
      base.class_attribute :arel_attribute_types, instance_accessor: false, default: {}
    end

    module InstanceMethods
      # Rails internals (associations, preloading) read FK/PK values via
      # _read_attribute, not via the public method. For arel attributes that
      # have a Ruby getter defined, fall back to calling that method so
      # belongs_to/has_many with virtual FKs work.
      def _read_attribute(attr_name, &block) # :nodoc:
        value = super
        if value.nil? && self.class.arel_attribute?(attr_name) && respond_to?(attr_name)
          send(attr_name)
        else
          value
        end
      end
    end

    module ClassMethods
      # Define an attribute backed by an arel expression.
      #
      # The block receives the arel table and returns an arel node.
      # This allows the attribute to be used in WHERE, ORDER BY, and SELECT clauses.
      #
      #   define_arel_attribute :parent_id, :integer do |t|
      #     Arel::Nodes::NamedFunction.new('SUBSTR', [t[:path], ...])
      #   end
      #
      def define_arel_attribute(name, type, &block)
        raise ArgumentError, "arel block is required for define_arel_attribute" unless block
        self.arel_aliases = arel_aliases.merge(name.to_s => block)
        self.arel_attribute_types = arel_attribute_types.merge(name.to_s => type)
      end

      # Compatibility with virtual_attributes API
      def virtual_attribute(name, type, options = {})
        raise ArgumentError, "arel option is required" unless options[:arel]
        define_arel_attribute(name, type, &options[:arel])
      end

      def virtual_attribute_names
        arel_aliases.keys
      end

      def arel_attribute?(name)
        arel_aliases.key?(name.to_s)
      end

      def attribute_supported_by_sql?(name)
        column_names.include?(name.to_s) || arel_attribute?(name)
      end

      def load_schema!
        super
        arel_attribute_types.each do |name, type|
          register_arel_type(name, type)
        end
      end

      def arel_table
        @arel_table ||= ArelAttribute::TableProxy.new(table_name, klass: self)
      end

      private

      # Register the type for an arel attribute so ActiveRecord can type-cast
      # values in WHERE clauses.
      def register_arel_type(name, type)
        if type.is_a?(Symbol) || type.is_a?(String)
          type = ActiveRecord::Type.lookup(type, adapter: ActiveRecord::Type.adapter_name_from(self))
        end
        attribute_types[name] = type
      end
    end
  end
end
