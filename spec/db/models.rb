class TestRecord < ActiveRecord::Base
  self.abstract_class = true

  include ArelAttribute::Base
  include ArelAttribute::ArelAggregate

  # unfortunatly, this is not on associations
  def self.factory(count, attrs)
    Array(count) { create(attrs) }
  end
end

class Author < TestRecord
  # basically a :parent_id relationship
  belongs_to :teacher, :foreign_key => :teacher_id, :class_name => "Author", :optional => true
  has_many :students, :foreign_key => :teacher_id, :class_name => "Author"
  has_many :books
  has_many :ordered_books,   -> { ordered },   :class_name => "Book"
  has_many :published_books, -> { published }, :class_name => "Book"
  has_many :wip_books,       -> { wip },       :class_name => "Book"
  has_and_belongs_to_many :co_books,           :class_name => "Book"
  has_many :bookmarks,                         :class_name => "Bookmark", :through => :books
  has_many :photos, :as => :imageable, :class_name => "Photo"
  has_one :current_photo, -> { all.merge(Photo.order(:id => :desc)) }, :as => :imageable, :class_name => "Photo"
  has_one :fancy_photo, -> { where(:purpose => "fancy") }, :as => :imageable, :class_name => "Photo"
  has_one :first_book, -> { order(:id) }, :class_name => "Book"

  arel_attribute(:current_photo_id, :integer) do |t|
    photos_table = Photo.arel_table
    photos_table
      .where(photos_table[:imageable_type].eq("Author"))
      .where(photos_table[:imageable_id].eq(t[:id]))
      .order(photos_table[:id].desc)
      .take(1)
      .project(photos_table[:id])
  end

  def current_photo_id
    if has_attribute?("current_photo_id")
      self["current_photo_id"]
    else
      photos.order(:id => :desc).limit(1).pick(:id)
    end
  end

  arel_total :total_books, :books
  arel_total :total_books_published, :published_books
  arel_total :total_books_in_progress, :wip_books
  # same as total_books, but going through a relation with order
  arel_total :total_ordered_books, :ordered_books
  # virtual total using has_many :through
  arel_total :total_bookmarks, :bookmarks
  alias v_total_bookmarks total_bookmarks
  # virtual total using has_and_belongs_to_many
  arel_total :total_co_books, :co_books

  has_many :recently_published_books, -> { published.order(:created_on => :desc) },
           :class_name => "Book", :foreign_key => "author_id"

  arel_total :total_recently_published_books, :recently_published_books
  arel_average :average_recently_published_books_rating, :recently_published_books, :rating
  arel_minimum :minimum_recently_published_books_rating, :recently_published_books, :rating
  arel_maximum :maximum_recently_published_books_rating, :recently_published_books, :rating
  arel_sum :sum_recently_published_books_rating, :recently_published_books, :rating
  # delegate to parent (self-join)
  arel_attribute :teacher_name, :string, through: :teacher, source: :name
  # delegate to parent's parent (chained self-join)
  arel_attribute :teacher_teacher_name, :string, through: :teacher, source: :teacher_name
  # delegate to has_one (polymorphic)
  arel_attribute :current_photo_description, :string, through: :current_photo, source: :description
  # delegate to has_one with scope
  arel_attribute :fancy_photo_description, :string, through: :fancy_photo, source: :description

  has_many :named_books, -> { where.not(:name => nil) }, :class_name => "Book"
  # depends on Book#author_name delegate being filterable in SQL
  has_many :books_with_authors, -> { where.not(:author_name => nil).where.not(:name => nil) }, :class_name => "Book"
  arel_total :total_named_books, :named_books
  alias v_total_named_books total_named_books

  def nick_or_name
    has_attribute?("nick_or_name") ? self["nick_or_name"] : nickname || name
  end

  # sorry. no creativity on this one (just copied nick_or_name)
  def name_no_group
    has_attribute?("name_no_group") ? self["name_no_group"] : nickname || name
  end

  # simple arel attributes for testing basic functionality
  arel_attribute(:doubled, :integer) { |t| t[:teacher_id] + t[:teacher_id] }
  arel_attribute(:upper_name, :string) { |t| Arel::Nodes::NamedFunction.new("UPPER", [t[:name]]) }

  # arel attribute with grouping wrapping
  arel_attribute(:nick_or_name, :string) do |t|
    t.grouping(Arel::Nodes::NamedFunction.new("COALESCE", [t[:nickname], t[:name]]))
  end

  # arel attribute without grouping — tests that non-Grouping arel nodes work
  arel_attribute(:name_no_group, :string) do |t|
    Arel::Nodes::NamedFunction.new("COALESCE", [t[:nickname], t[:name]])
  end

  # has_one ordered by a virtual attribute (arel_total) — tests that scoped
  # has_one works when the ordering column is itself a correlated subquery
  has_one :book_with_most_bookmarks, -> { order(:total_bookmarks => :desc) }, :class_name => "Book"

  # delegate to has_one
  arel_attribute :first_book_name, :string, through: :first_book, source: :name
  # delegate to a delegate (has_one -> belongs_to delegate)
  arel_attribute :first_book_author_name, :string, through: :first_book, source: :author_name
  # arel attribute that builds on a delegate
  arel_attribute(:upper_first_book_author_name, :string) { |t| Arel::Nodes::NamedFunction.new("UPPER", [t[:first_book_author_name]]) }

  def upper_first_book_author_name
    has_attribute?("upper_first_book_author_name") ? self["upper_first_book_author_name"] : first_book_author_name&.upcase
  end

  def self.create_with_books(count)
    create!(:name => "foo").tap { |author| author.create_books(count) }
  end

  def create_books(count, create_attrs = {})
    Array.new(count) do
      books.create({:name => "bar"}.merge(create_attrs))
    end
  end
end

class Book < TestRecord
  has_many :bookmarks
  belongs_to :author
  has_and_belongs_to_many :co_authors, :class_name => "Author"
  belongs_to :author_or_bookmark, :polymorphic => true, :foreign_key => "author_id", :foreign_type => "author_type"

  has_many :photos, :as => :imageable, :class_name => "Photo"
  has_one :current_photo, -> { all.merge(Photo.order(:id => :desc)) }, :as => :imageable, :class_name => "Photo"

  scope :ordered,   -> { order(:created_on => :desc) }
  scope :published, -> { where(:published => true)  }
  scope :wip,       -> { where(:published => false) }
  # delegate to belongs_to (different table)
  arel_attribute :author_name, :string, through: :author, source: :name
  # delegate to a polymorphic has_one
  arel_attribute :current_photo_description, :string, through: :current_photo, source: :description

  # arel attribute that builds on a delegate
  arel_attribute(:upper_author_name, :string) { |t| Arel::Nodes::NamedFunction.new("UPPER", [t[:author_name]]) }

  def upper_author_name
    has_attribute?("upper_author_name") ? self["upper_author_name"] : author_name&.upcase
  end

  # chained arel attribute: builds on upper_author_name which builds on author_name delegate
  arel_attribute(:upper_author_name_def, :string) { |t| Arel::Nodes::NamedFunction.new("COALESCE", [t[:upper_author_name], Arel.sql("'other'")]) }

  def upper_author_name_def
    has_attribute?("upper_author_name_def") ? self["upper_author_name_def"] : upper_author_name || "other"
  end
end

class Bookmark < TestRecord
  belongs_to :book
end

class Photo < TestRecord
  belongs_to :imageable, :polymorphic => true
end

# these are just here so we don't monkey patch them in our tests
class SpecialBook < Book
  default_scope { where(:special => true) }

  self.table_name = 'books'
end

class SpecialAuthor < Author
  self.table_name = 'authors'

  has_many :special_books,
           :class_name => "SpecialBook", :foreign_key => "author_id"
  has_many :published_special_books, -> { published },
           :class_name => "SpecialBook", :foreign_key => "author_id"

  arel_total :total_special_books, :special_books
  arel_total :total_special_books_published, :published_special_books
end

module ArelAncestry
  def self.included(base)
    base.include(ArelAttribute::SqlDetection)
    base.extend(ClassMethods)
    # include other schemes for making converting these keys
    base.extend(MaterializedPath2)
  end

  module ClassMethods
    # Define arel-backed virtual attributes for a materialized_path2 ancestry column.
    #
    # @param ancestry_column [Symbol] the column storing the path (e.g. :path)
    # @param prefix [false, String, Symbol] prefix for attribute names (false = no prefix)
    # @param attributes [true, false, Array<Symbol>] which attributes to define
    #   true = all (:path_ids, :root_id, :parent_id, :child_path)
    #   false = none
    #   Array = only the listed attributes
    # @param associations [true, false] whether to define parent/children/root associations
    def arel_ancestry(ancestry_column, prefix: false, attributes: true, associations: true)
      col = ancestry_column.to_sym
      pk = primary_key.to_sym

      attr_list = if attributes == true
                    [:path_ids, :root_id, :parent_id, :child_path]
                  elsif attributes == false
                    []
                  else
                    Array(attributes).map(&:to_sym)
                  end

      if attr_list.include?(:path_ids)
        # arel_attribute(:path_ids, :integer) do |t|
        #   materialized_path2_root_id_arel(t, pk, col)
        # end
        define_method(:path_ids) do
          self.class.materialized_path2_path_ids_ruby(send(col))
        end
      end

      if attr_list.include?(:root_id)
        arel_attribute(:root_id, :integer) do |t|
          materialized_path2_root_id_arel(t, pk, col)
        end

        define_method(:root_id) do
          self["root_id"] || self.class.calculate_materialized_path2_root_id_ruby(id, path_ids)
        end
      end

      if attr_list.include?(:parent_id)
        arel_attribute(:parent_id, :integer) do |t|
          materialized_path2_parent_id_arel(t, pk, col)
        end

        # For unsaved records (e.g. children.build), the path isn't set yet
        # so the ruby fallback returns nil. Check @arel_attribute_values
        # (populated by parent_id=) to handle that case.
        define_method(:parent_id) do
          @arel_attribute_values&.dig("parent_id") || self["parent_id"] ||
            self.class.materialized_path2_parent_id_ruby(id, path_ids)
        end

        # AR associations call parent_id= when building children via
        # `a.children.create!`. _write_attribute stores the value so
        # both the getter and _read_attribute (used by AR internals)
        # can find it before the record is saved.
        define_method(:parent_id=) do |value|
          _write_attribute("parent_id", value)
        end
      end

      if attr_list.include?(:child_path)
        arel_attribute(:child_path, :string) do |t|
          materialized_path2_child_path_arel(t, pk, col)
        end

        define_method(:child_path) do
          self["child_path"] || self.class.materialized_path2_child_path_ruby(id, send(col))
        end

        # local ruby helper only. not sure if these are needed
        # should they be using :child_path instead of pk, col?

        self.singleton_class.define_method(:child_path_wild_arel) do |t|
          materialized_path2_child_path_wild_arel(t, pk, col)
        end

        define_method(:child_path_wild_ruby) do
          self.class.materialized_path2_child_path_wild_ruby(id, send(col))
        end
      end

      if associations
        if attr_list.include?(:root_id)
          belongs_to :root, foreign_key: :root_id, class_name: name, optional: true
        end
        if attr_list.include?(:parent_id)
          belongs_to :parent, foreign_key: :parent_id, class_name: name, inverse_of: :children, optional: true
          has_many :children, foreign_key: :parent_id, class_name: name, inverse_of: :parent

          before_validation :_set_path_from_parent, on: :create
          define_method(:_set_path_from_parent) do
            self[col] = parent.child_path if parent
          end
          private :_set_path_from_parent
        end
      end

      # TODO: siblings does not include self
      # has_many :siblings, foreign_key: :parent_id, primary_key: :parent_id, class_name: "Person"
      has_many :siblings, foreign_key: ancestry_column, primary_key: ancestry_column, class_name: "Person"

      # descendants: target.path LIKE owner.child_path || '%'
      descendants_strategy = Module.new do
        define_method(:join_arel) do |owner_table, foreign_table|
          where(foreign_table[col].matches(child_path_wild_arel(owner_table)))
        end
        define_method(:join_records) do |owners, foreign_table|
          owners_alias = arel_table.alias("owners_for_preload")
          on_clause = foreign_table[col].matches(child_path_wild_arel(owners_alias))
          joins(foreign_table.join(owners_alias).on(on_clause).join_sources)
            .where(owners_alias[primary_key].in(owners.map(&:id)))
        end
        define_method(:where_record) do |owner, foreign_table|
          where(foreign_table[col].matches(owner.child_path_wild_ruby))
        end
        define_method(:match?) do |record, owner|
          record.path.start_with?(owner.child_path)
        end
      end

      has_many :descendants, class_name: "Person", join_strategy: descendants_strategy
      arel_total :total_descendants, :descendants

      # ancestors: owner.path LIKE target.child_path || '%'
      ancestors_strategy = Module.new do
        define_method(:join_arel) do |owner_table, foreign_table|
          where(owner_table[col].matches(child_path_wild_arel(foreign_table)))
        end
        define_method(:join_records) do |owners, foreign_table|
          owners_alias = arel_table.alias("owners_for_preload")
          on_clause = owners_alias[col].matches(child_path_wild_arel(foreign_table))
          joins(foreign_table.join(owners_alias).on(on_clause).join_sources)
            .where(owners_alias[primary_key].in(owners.map(&:id)))
        end
        define_method(:where_record) do |owner, foreign_table|
          owner_col = Arel::Nodes::Quoted.new(owner.send(col))
          where(owner_col.matches(child_path_wild_arel(foreign_table)))
        end
        define_method(:match?) do |record, owner|
          owner.path.start_with?(record.child_path)
        end
      end

      has_many :ancestors, class_name: "Person", join_strategy: ancestors_strategy

      # TODO: subtree = self + descendants
      has_many :subtree, ->(person) { where(arel_table[ancestry_column].matches("#{person.child_path_wild_ruby}").or(arel_table[:id].eq(person.id))) },
               class_name: "Person", foreign_key: :path, primary_key: :child_path
    end

    private

    def sql_fn(name, *args)
      Arel::Nodes::NamedFunction.new(name, args)
    end

    def sql_cast(expr, type)
      Arel::Nodes::NamedFunction.new("CAST", [Arel::Nodes::As.new(expr, Arel.sql(type))])
    end

    def sql_position(str, sub)
      sql_fn(is_pg?("STRPOS", "INSTR"), str, sub)
    end

    def sql_case_root(path, root_val, not_root)
      Arel::Nodes::Case.new(path).when(Arel.sql("'/'")).then(root_val).else(not_root)
    end
  end
  module MaterializedPath2
    def materialized_path2_root_id_arel(t, pk = :id, ancestry_column = :path)
      path = t[ancestry_column]
      stripped = sql_fn("SUBSTRING", path, 2)     # => 1/2/3/
      s_pos = sql_fn(is_pg?("STRPOS", "INSTR"), stripped, Arel.sql("'/'")) - 1
      segment = sql_fn("SUBSTR", path, 2, s_pos)    # => 1
      sql_case_root(path, t[pk], sql_cast(segment, is_mysql?("UNSIGNED", "INTEGER")))
    end

    def calculate_materialized_path2_root_id_ruby(id, ancestry_ids)
      ids = ancestry_ids
      ids.empty? ? id : ids.first
    end

    def materialized_path2_parent_id_arel(t, pk = :id, ancestry_column = :path)
      path = t[ancestry_column]
      slash = Arel.sql("'/'")
      empty = Arel.sql("''")
      last_segment =
        if is_mysql?
          # SUBSTRING_INDEX(SUBSTRING_INDEX(path, '/', -2), '/', 1) of /1/2/3/
          parent_slash = sql_fn("SUBSTRING_INDEX", [path, slash, -2]) # => 3/
          sql_fn("SUBSTRING_INDEX", [parent_slash, slash, 1, ])       # => 3
        else
          # RTRIM(REPLACE(path, RTRIM(RTRIM(path, '/'), REPLACE(path, '/', '')), ''), '/')
          no_slash_chars = sql_fn("REPLACE", path, slash, empty)                # => 123
          no_trailing_slash = sql_fn("RTRIM", path, slash)                      # => /1/2/3
          front = sql_fn("RTRIM", no_trailing_slash, no_slash_chars)            # => /1/2/
          sql_fn("RTRIM", sql_fn("REPLACE", path, front, empty), slash)         # => 3/ => 3
        end
      sql_case_root(path, Arel.sql("NULL"), sql_cast(last_segment, is_mysql?("UNSIGNED", "INTEGER")))
    end

    def materialized_path2_parent_id_ruby(id, ancestry_ids)
      ids = ancestry_ids
      ids.empty? ? nil : ids.last
    end

    def materialized_path2_child_path_arel(t, pk = :id, ancestry_column = :path)
      Arel::Nodes::Concat.new(t[ancestry_column], t[pk]).concat(Arel.sql("'/'"))
    end

    def materialized_path2_child_path_ruby(id, ancestry)
      "#{ancestry}#{id}/"
    end

    def materialized_path2_child_path_wild_arel(t, pk = :id, ancestry_column = :path) # optimization to take path?
      Arel::Nodes::Concat.new(t[ancestry_column], t[pk]).concat(Arel.sql("'/%'"))
    end

    def materialized_path2_child_path_wild_ruby(id, ancestry) #optimization to take path?
      "#{ancestry}#{id}/%"
    end

    # def materialized_path2_path_ids_arel(t, pk = :id, ancestry_column = :path)
    # end

    def materialized_path2_path_ids_ruby(path)
      return [] if path.blank? || path == "/"
      path[1..].split("/").map(&:to_i)
    end
  end
end

class Person < ActiveRecord::Base
  include ArelAttribute::Base
  include ArelAttribute::ArelAggregate
  include ArelAncestry

  arel_ancestry :path, prefix: false, attributes: true, associations: true
  scope :roots, -> { where(path: "/") }

  arel_total :total_descendants, :descendants

  def self.factory(count = 3, start: "a".ord)
    count.times.inject([]) do |ac, i|
      ac << create!(name: (start + i).chr, path: ac.last&.child_path || "/")
    end
  end
end
