# frozen_string_literal: true

require "active_support/concern"
require "active_record"
require "arel"
# ours
require "arel/nodes/arel_attribute"
require "arel_attribute/version"
require "arel_attribute/table_proxy"
require "active_support" #concern, class_attribute
module ArelAttribute
  class Error < StandardError; end

  module Base
    def self.included(base)
      puts "****** #{base}.included ******"
      base.extend  ArelAttribute::Base::ClassMethods
      base.include ArelAttribute::Base::InstanceMethods
      base.class_attribute :arel_aliases, instance_accessor: false, default: {} # :internal:
      base.class_attribute :linked_attributes_to_define, instance_accessor: false, default: {} # :internal:
    end

    module InstanceMethods
      # the linked attributes have no access to the main record. this is setting the context
      # could also pass in @attributes instead of self
      def initialize_internals_callback
        super
        self.class.linked_attributes_to_define.each do |name, (type, value)|
          @attributes[name].rec = self if value
        end
      end
    end

    module ClassMethods
      def define_linked_attribute(name, type, &block)
        # when block is nil:
        #   we are reusing this for arel. just want to define a type
        #   if it is already defined (don't want to possibly blow away block definition)
        if !block.nil? || !linked_attributes_to_define[name.to_s]
          self.linked_attributes_to_define = linked_attributes_to_define.merge(name.to_s => [type, block])
        end
      end

      def define_arel_attribute(name, type, **options, &block)
        # note: block for define_linked_attribute is the ruby value block
        # not the arel block value
        define_linked_attribute(name, type)
        self.arel_aliases = arel_aliases.merge(name.to_s => block)
      end

      def load_schema!
        super
        linked_attributes_to_define.each do |name, (type, value)|
          type = ActiveRecord::Type.lookup(type, adapter: ActiveRecord::Type.adapter_name_from(self))
          # the type information is read from the model/relation and not from the attribute
          # so we need to put it into the model
          attribute_types[name] = type
          # arel only attributes did not set the value (a block)
          if value
            # bad stuff follows:
            # we should be calling define_attribute instead of cherry picking it
            # define_attribute => define_default_attribute
            _default_attributes[name] = ArelAttribute::LinkedAttribute.new(name, value, type)
          end
        end
      end

      def arel_attribute?(name) ; !!arel_aliases[name.to_s] ; end

      def arel_table # :nodoc:
        @arel_table ||= ArelAttribute::TableProxy.new(table_name, :klass => self)
      end
      # private. use arel_table[name] instead
      def arel_attribute(name, table = arel_table) # :nodoc:
        arell = arel_aliases[name.to_s]
        Arel::Nodes::ArelAttribute.new(arell[table], name.to_s, table) if arell
      end
    end
  end
end
# require 'active_support'
# ActiveSupport.on_load :active_record do
#
#   include ArelAttribute::Base
# end
