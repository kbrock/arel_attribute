#!/usr/bin/env ruby

# TODO: research ARecord: with_cast_value, QueryAttribute
# TODO: research AModel:  alias_attribute, define_attribute_method
# TODO: can we leverage alias_attribute for arel?
# TODO: LINK attribute to read value from parent attribute # via caster or custom type?
#       think there is a hook in FromDatabase (not used anywhere)
#       currently a value is always set and we go in and set again (prefer to never set)
# TODO: do we want to detect parent_id and change behavior?
# TODO: virtual_delegate

require "active_record"
require_relative "lib/arel_attribute"
require "minitest/autorun"
require "logger"
require "byebug"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = Logger::WARN

def byebug_verbose? ; byebug if verbose? ; end
def verbose? ; ActiveRecord::Base.logger.level == Logger::DEBUG ; end
def verbose
  old_level, ActiveRecord::Base.logger.level = ActiveRecord::Base.logger.level, Logger::DEBUG
  yield
ensure
  ActiveRecord::Base.logger.level = old_level
end

puts "---"
puts "  Ruby: #{RUBY_VERSION}"
puts "  ActiveRecord: #{ActiveRecord.version}"
puts "  Database: #{ActiveRecord::Base.connection.adapter_name}\n\n"
puts "---", ""

# going to define after Person class is defined
# that way we are sure we are not loading db too early
def define_schema
  ActiveRecord::Schema.define do
    create_table :people, force: true do |t|
      t.string :path, null: false, default: "/"
      t.string :name
    end
  end
end

module Ancestry
  extend ActiveSupport::Concern
  included do
    class_attribute :ancestry_delimiter, default: "/"
  end

  # dynamically defined:
  def path=(value)
    write_propagate("path", value)
  end

  def child_path=(value)
    write_propagate("path", self.class.extract_path_up(value))
  end

  # drop method?
  def write_propagate(fld_name, value, **opts)
    write_attribute(fld_name, value)
    propagate_path_changed(fld_name, **opts)
  end

  # TODO: wish this were more lazy
  # NOTE: we only need to propagate "attributes" that are in db, or used in joins
  # so by this, parent_id does not need to be in there
  # @param prefix [String] (default: nil) typically "#{fld_name}_"
  def propagate_path_changed(fld_name="path", prefix: nil, parent_id: false)
    prefix = "#{fld_name}_" unless fld_name == "path"
    value = attribute_before_type_cast(fld_name)
    write_attribute("#{prefix}root_id", self.class.extract_root_id(value, id)&.to_i)
    write_attribute("#{prefix}parent_id", self.class.extract_path_id(value, id, -1)&.to_i) if parent_id
    write_attribute("#{prefix}child_path", self.class.extract_path_down(value, id))
  end

  # after_initialize, after_find hooks
  def propagate_paths_find(fld_name = "path", **opts)
    if has_attribute?(fld_name) # since this is db, it knows if it is there
      propagate_path_changed(fld_name, **opts)
    # TODO: prefer _has_attribute?(attr_name), but attributes always say yes
    elsif (value = _read_attribute("#{fld_name}_path")).present?
      write_propagate(fld_name, self.class.extract_path_up(value), **opts)
    end
  end

  # after_save hook (only from new_record)
  def propagate_paths_create(fld_name = "path", **opts)
    # attributes are derived from the path and the id
    if saved_change_to_attribute?(@primary_key) || saved_change_to_attribute?(fld_name)
      propagate_path_changed(fld_name, **opts)
    end
  end

  class_methods do
    # ancestry format /id/id/id/
    def extract_root_id(value, id) value.blank? || value == '/' ? id : extract_path_ids(value)[0] ; end # used once
    def extract_path_ids(value) ; value.blank? || value == '/' ? [] : value[1..].split('/') ; end
    def extract_path_up(value) ; value[0, value.rindex('/', value.length - 1) - 1] ; end # parent.path
    def extract_path_down(value, id) ; "#{value}#{id}/" ; end # child.path
    def extract_path_id(value, id, offset)
      value == '/' ? nil : extract_path_ids(value)[offset]&.to_i
    end
#      when -1  then value[(value.rindex('/', value.length - 1) + 1)..]
  end
end

# TODO: use pure arel instead of builder here?
module SqlBuilderHelpers
  def q(x='') ; "\'#{x}\'" ; end
  def col(table, column) ; "\"#{table.name}\".\"#{column}\"" ; end
  def fn(*args) ; nm = args.shift ; "#{nm.upcase}(#{args.join(", ")})" ; end
  def cast(col, type) ; "CAST(#{col} AS #{type})" ; end
  def slash(col, not_value, value) ; "(CASE WHEN #{col} = '/' THEN #{not_value} ELSE #{value} END)" ; end
  # NOTE: pg and sqlite only. alt: fn("concat", *args) ; end
  def concat(*args) ; args.join("||") ; end
end

#############################################################
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  include ArelAttribute::Base
  include Ancestry
end

class Person < ApplicationRecord
  extend SqlBuilderHelpers
  # TODO: what is best way to determine if attributes was in the select (esp. if value.nil?)
  # TODO: have auto set elsewhere?
  # not sure if initialize necessary
  after_initialize :propagate_paths_find
  after_find :propagate_paths_find

  # after create?
  after_save :propagate_paths_create

  define_arel_attribute :root_id, :integer do |table|
    path = col(table, "path")
    Arel.sql(slash(path, col(table, primary_key), cast(
      fn("substr", path, 2, fn("instr", fn("ltrim", path, q('/')), q('/')) + " - 1"), "INTEGER")))
  end
  attribute :root_id, :integer
  # NOTE: much easier in postgres (also easier in mp1)
  # https://stackoverflow.com/questions/21388820/how-to-get-the-last-index-of-a-substring-in-sqlite
  # ALL_CHARACTERS_IN_STRING = REPLACE(#{path}, '/', '')
  # TODO: ? use ALL_CHARACTERS_IN_STRING = '0123456789ABCDEF_-
  # FRONT = RTRIM(#{path}, ALL_CHARACTERS_IN_STRING) = pull off the last value
  #   if we are mp2 with a trailing slash, need to RTRIM(path, '/')
  # REPLACE(path, FRONT) ends up with the right field (mp2 needs to remove trailing slash)
  # TODO: FIX. something went askew
  define_arel_attribute :parent_id, :integer do |table|
    path = col(table, "path")
    Arel.sql(slash(path, "NULL", cast(
      fn("RTRIM", fn("REPLACE", path, fn("RTRIM", fn("RTRIM", path, q('/')), fn("REPLACE", path, q('/'), q())), q()), q('/')),
      "INTEGER")))
  end
  def parent_id=(parent_id) ; self.path = parent_id ? self.class.find(parent_id)&.child_path : "/"; end
  def parent_id ; self.class.extract_path_id(path, id, -1)&.to_i ; end

  define_arel_attribute :child_path, :string do |table|
    Arel.sql(concat(col(table, "path"), col(table, "id"), q('/')))
  end
  attribute :child_path, :string

  scope :roots, -> { where(:path => '/') }

  belongs_to :root,   foreign_key: :root_id, class_name: self.name
  # NOTE: would prefer parent_id, but creating with a given parent doesn't assign correctly
  #belongs_to :parent, foreign_key: :parent_id, class_name: self.name
  belongs_to :parent, foreign_key: :path, primary_key: :child_path, class_name: self.name, inverse_of: :children
  def parent=(parent) ; self.path = parent.child_path ; end
  def parent_id=(parent_id) ; super ; puts "why did you call parent_id=" ; end

  has_many :siblings, foreign_key: :path, primary_key: :path, class_name: self.name
  # but then inefficient to use children.create() (would pass parent_id and cause extra lookup) - override create/build
  # has_many :children, primary_key: :parent_id, class_name: self.name, inverse_of: :parent
  has_many :children, foreign_key: :path, primary_key: :child_path, class_name: self.name, inverse_of: :parent

  # if caching parent_id, this may be good. (unsure) caching child_path may be good
  # has_many :children, foreign_key: :parent_id, class_name: self.name, inverse_of: :parent
  # belongs_to :parent, foreign_key: :parent_id, class_name: self.name

  # TODO: fix for includes/preload
  # TODO: prevent descendants.create -
  # TODO: this isn't quite right
  has_many :descendants, foreign_key: :root_id, primary_key: :root_id, class_name: self.name
  # def descendants
  #   self.class.where(self.class.arel_table[:path].matches("#{path}%", nil, false))
  # end

  # testing
  def self.factory(count = 3, start: 'a'.ord)
    Person.delete_all
    count.times.inject([]) do |ac, i|
      ac << create!(name: (start+i).chr, path: ac.last&.child_path || "/")
    end
  end
end

##########################################################################################
# tests

define_schema

class BugTest < Minitest::Test
  i_suck_and_my_tests_are_order_dependent! # not needed. It is easier to deal with

  def assert_objects(expected, actual)
    if expected.kind_of?(Array)
      assert_equal expected.map { |p| p&.id }, actual.map { |p| p&.id }
    else
      assert_equal 1, actual.count
      assert_equal expected&.id, actual&.first&.id
    end
  end

  def test_arel_attribute?
    assert Person.arel_attribute?("child_path")
    refute Person.arel_attribute?("name")
  end

  def test_attr
    assert_equal 1, Person.new(id: 1, name: "a").root_id
    assert_equal 1, Person.new(name: "a", path: "/1/").root_id
    assert_equal 2, Person.new(name: "a", path: "/2/").root_id
    assert_equal 2, Person.find(Person.create!(name: "a", path: "/2/").id).root_id
  end

  def test_select
    a, b, c = Person.factory(3)

    # BROKEN: select(:root_id), select("root_id")
    # ppl = Person.select(:id, :path, :name, :root_id).order(:id).load
    # assert_equal [a.id, a.id, a.id], ppl.map(&:root_id)

    # WORKING
    # use the following for tracing the issue:
    ppl = Person.select(:id, :path, :name, "people.root_id").order(:id).load
    assert_equal [a.id, a.id, a.id], ppl.map(&:root_id)

    root_with_alias = Person.arel_table["root_id"].as("root_id")
    ppl = Person.select(:id, :path, :name, root_with_alias).order(:id).load
    assert_equal [a.id, a.id, a.id], ppl.map(&:root_id)

    ppl = Person.select(:id, :name, root_with_alias).order(:id).load # no path variable
    assert_equal [a.id, a.id, a.id], ppl.map(&:root_id)
  end

  def test_where
    a, b, c = Person.factory(3)

    ppl = Person.where(:root_id => a.id).order(:id)
    assert_objects [a, b, c], ppl

    # casting value to the correct type
    ppl = Person.where(:root_id => a.id.to_s).order(:id)
    assert_objects [a, b, c], ppl

    ppl = Person.where("root_id" => a.id).order(:id)
    assert_objects [a, b, c], ppl

    ppl = Person.where(Person.arel_table["root_id"].eq(a.id)).order(:id)
    assert_objects [a, b, c], ppl

    ppl = Person.where(:parent_id => a.id).order(:id)
    assert_objects [b], ppl

    # BROKEN: casting value to the correct type
    # ppl = Person.where(:parent_id => a.id.to_s).order(:id)
    # assert_objects [b], ppl

    ppl = Person.where("parent_id" => a.id).order(:id)
    assert_objects [b], ppl

    ppl = Person.where(Person.arel_table["parent_id"].eq(a.id)).order(:id)
    assert_objects [b], ppl
  end

  def test_order
    a, b, c = Person.factory(3)

    root_sort = Arel::Nodes::Ascending.new(Person.arel_table["parent_id"]).nulls_last
    ppl = Person.order(root_sort, :id)
    assert_objects [b, c, a], ppl

    # NOTE: db dependent around nulls
    ppl = Person.order(:parent_id, :id)
    assert_objects [a, b, c], ppl

    # NOTE: db dependent around nulls
    ppl = Person.order(Person.arel_table["parent_id"], :id)
    assert_objects [a, b, c], ppl
  end

  # can't remember the exact use case that causes the distinct to freak when not in a sql clause
  def test_distinct_order
    Person.factory(3)
    Person.all.distinct.order(:root_id).load
    # making sure it doesn't blow up
  end

  def test_count
    a, b, c = Person.factory(3)

    # BROKEN: count("root_id") count(:root_id)
    assert_equal 2, Person.count(Person.arel_table["parent_id"])
    assert_equal 2, Person.count("people.parent_id")
  end

  def test_belongs_to
    a, b, c = Person.factory(3)

    assert_equal a.id, b.root_id
    assert_equal a.id, c.root&.id
    assert_equal a.id, b.parent_id
    assert_equal a.id, b.parent&.id

    assert_equal a.id, c.root_id
    assert_equal a.id, c.root&.id
    assert_equal b.id, c.parent_id
    assert_equal b.id, c.parent&.id
  end

  def test_after_create
    a = Person.create
    assert_equal "/", a.path
    assert_equal "/#{a.id}/", a.child_path
    assert_nil a.parent_id
  end

  def test_has_many
    a, b, c = Person.factory(3)
    assert_objects [b], a.children.order(:id)
    assert_objects [c], b.children.order(:id)
  end

  # making sure work from created records AND saved_records
  def test_has_many_create
    a, b, c = Person.factory(3)
    d = a.children.create!
    assert_objects [b, d], a.children.order(:id)
    assert_objects [b, d], a.reload.children.order(:id)
    assert_objects [b, d], b.siblings.order(:id)
    assert_objects [b, d], b.reload.siblings.order(:id)
  end

  def test_record_scopes # specific to a record
    a, b, c = Person.factory(3)
    assert_objects [a, b, c], a.descendants.order(:id)
  end

  def test_join
    a, b, c = Person.factory(3)
    b.update(:name => "mid")

    ppl = Person.joins(:children).where(:children => {:name => "mid"}).order(:id)
    assert_objects [a], ppl
    ppl = Person.joins(:children).where(:children => {:root_id => a.id}).order(:id)
    assert_objects [a, b], ppl
  end

  # TODO: count queries to ensure actually preloaded
  def test_include_root
    a, b, c = Person.factory(3)

    ppl = Person.includes(:root).order(:id).load
    assert_objects [a, a, a], ppl.map(&:root)
    #puts ppl.map { |p| "p: #{p.name} (#{p.id}), parent: #{p&.parent&.name || "none"} (#{p&.parent&.id || "none"})"}
  end

  def test_include_parent
    a, b, c = Person.factory(3)

    ppl = Person.includes(:parent).order(:id).load
    assert_objects [nil, a, b], ppl.map(&:parent)
  end

  def test_include_all
    a, b, c = Person.factory(3)
    ppl = Person.includes(:descendants).order(:id).load
  end

  # TODO: count queries to ensure actually preloaded
  def test_preload_root
    a, b, c = Person.factory(3)
    ppl = Person.preload(:root).order(:id).load
    assert_equal a.id, a.root&.id
    assert_equal a.id, b.root.id
    assert_equal a.id, c.root.id
  end

  # TODO: count queries to ensure actually preloaded
  def test_preload
    a, b, c = Person.factory(3)
    ppl = Person.preload(:parent).order(:id).load
    assert_equal b.parent_id, a.id
    assert_equal b.parent.id, a.id
    assert_equal c.parent_id, b.id
    assert_equal c.parent.id, b.id
  end

  def test_preloads_all
    # skip "fails" # TODO: BROKEN
    a, b, c = Person.factory(3)
    ppl = Person.includes(:descendants).order(:id).load
  end
end