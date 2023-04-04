# frozen_string_literal: true

# using UserProvidedDefault (vs FromUser) b/c unsure about marshal_dump
require "active_model/attribute/user_provided_default"

# we really should not be doing this.
# all other attributes only reference the record in hand
# this ties into the rest of the record

module ArelAttribute
  class LinkedAttribute < ActiveModel::Attribute::UserProvidedDefault
    # so we can set the lamba later
    rw :rec
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
