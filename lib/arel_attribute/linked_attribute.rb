# frozen_string_literal: true

# using UserProvidedDefault (vs FromUser) b/c unsure about marshal_dump
require "active_model/attribute/user_provided_default"

# we really should not be doing this.
# all other attributes only reference the attribute passed from the db
# this ties into the rest of the record's attributes
# But composite attributes have a getter return multiple columns
# we want multiple getters to access a single column

# TODO: think I wanted to put caching back in and make closer to original
# to do this, we'd have #clear_cache (called by the setter of the linked attributes)
module ArelAttribute
  class LinkedAttribute < ActiveModel::Attribute::UserProvidedDefault
    # Again, this goes against the way active record works
    # so we can set the lamba later
    attr_accessor :rec
    def initialize(name, value, type)
      # @user_provided_value = value ## part of super. add if changing to FromUser
      # value(default, lambda) and database value are not present
      super(name, value, type, nil)
    end

    def value_before_type_cast # removed caching
      user_provided_value.call(rec)
    end

    def value # removed caching
      type_cast(value_before_type_cast)
    end
  end
end
