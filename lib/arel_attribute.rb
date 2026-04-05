# frozen_string_literal: true

require "active_support/concern"
require "active_record"
require "arel"

require "arel/nodes/arel_attribute"
require "arel_attribute/version"
require "arel_attribute/table_proxy"
require "arel_attribute/relation_extension"
require "arel_attribute/arel_aggregate"
require "arel_attribute/arel_delegate"
require "arel_attribute/sql_detection"

module ArelAttribute
  class Error < StandardError; end
end

require "arel_attribute/arel_ruby"
require "arel_attribute/base"
