class TestRecord < ActiveRecord::Base
  self.abstract_class = true

  include ArelAttribute::Base
  include ArelAttribute::VirtualTotal

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

  virtual_total :total_books, :books
  virtual_total :total_books_published, :published_books
  virtual_total :total_books_in_progress, :wip_books
  # same as total_books, but going through a relation with order
  virtual_total :total_ordered_books, :ordered_books
  # virtual total using has_many :through
  virtual_total :total_bookmarks, :bookmarks
  alias v_total_bookmarks total_bookmarks
  # virtual total using has_and_belongs_to_many
  virtual_total :total_co_books, :co_books

  has_many :recently_published_books, -> { published.order(:created_on => :desc) },
           :class_name => "Book", :foreign_key => "author_id"

  virtual_total :total_recently_published_books, :recently_published_books
  virtual_average :average_recently_published_books_rating, :recently_published_books, :rating
  virtual_minimum :minimum_recently_published_books_rating, :recently_published_books, :rating
  virtual_maximum :maximum_recently_published_books_rating, :recently_published_books, :rating
  virtual_sum :sum_recently_published_books_rating, :recently_published_books, :rating
  # virtual_delegate :description, :to => :current_photo, :prefix => true, :type => :string
  # virtual_delegate :description, :to => :fancy_photo, :prefix => true, :type => :string
  # # delegate to parent relationship
  # virtual_delegate :name, :to => :teacher, :prefix => true, :type => :string
  # virtual_delegate :teacher_name, :to => :teacher, :prefix => true, :type => :string

  # PROBLEM: punted on this use case (ruby has many)
  # # This is here to provide a virtual_total of a virtual_has_many that depends upon an array of associations.
  # # NOTE: this is tailored to the use case and is not an optimal solution
  # def named_books
  #   # I didn't have the creativity needed to find a good ruby only check here
  #   books.select(&:name)
  # end

  # PROBLEM: punted on this use case (ruby only has many)
  # virtual_has_many that depends upon a hash of a virtual column in another model.
  # NOTE: this is tailored to the use case and is not an optimal solution
  # def books_with_authors
  #   books.select { |b| b.name && b.author_name }
  # end

  has_many :named_books, -> { where.not(:name => nil) }, :class_name => "Book"
  # books_with_authors depends on virtual_delegate :author_name in Book
  # has_many :books_with_authors, -> { where.not(:author_name => nil).not(:name => nil) }, :class_name => "Book"
  virtual_total :total_named_books, :named_books
  alias v_total_named_books total_named_books

  def nick_or_name
    has_attribute?("nick_or_name") ? self["nick_or_name"] : nickname || name
  end

  # sorry. no creativity on this one (just copied nick_or_name)
  def name_no_group
    has_attribute?("name_no_group") ? self["name_no_group"] : nickname || name
  end

  # simple arel attributes for testing basic functionality
  define_arel_attribute(:doubled, :integer) { |t| t[:teacher_id] + t[:teacher_id] }
  define_arel_attribute(:upper_name, :string) { |t| Arel::Nodes::NamedFunction.new("UPPER", [t[:name]]) }

  # a (local) virtual_attribute without a uses, but with arel
  # added in grouping (didn't use for other)
  virtual_attribute :nick_or_name, :string, :arel => (lambda do |t|
    t.grouping(Arel::Nodes::NamedFunction.new("COALESCE", [t[:nickname], t[:name]]))
  end)

  # We did not support arel returning something other than Grouping.
  # this is here to test what happens when we do
  virtual_attribute :name_no_group, :string, :arel => (lambda do |t|
    Arel::Nodes::NamedFunction.new("COALESCE", [t[:nickname], t[:name]])
  end)

  # def first_book_name
  #   has_attribute?("first_book_name") ? self["first_book_name"] : books.first.name
  # end

  # def first_book_author_name
  #   has_attribute?("first_book_author_name") ? self["first_book_author_name"] : books.first.author_name
  # end

  # def upper_first_book_author_name
  #   has_attribute?("upper_first_book_author_name") ? self["upper_first_book_author_name"] : first_book_author_name.upcase
  # end

  # PROBLEM: changed ruby
  # def famous_co_authors
  #   book_with_most_bookmarks&.co_authors || []
  # end

  # PROBLEM: changed ruby (and didn't implement)
  # basic attribute with uses that doesn't use a virtual attribute
  # def book_with_most_bookmarks
  #   books.max_by { |book| book.bookmarks.size }
  # end

  has_one :book_with_most_bookmarks, -> { order(:total_bookmarks => :desc) }, :class_name => "Book"
  # # PROBLEM: changed ruby virtual_attribute to delegate
  # # attribute using a relation
  # virtual_delegate :name, :to => :first_book, :prefix => true, :type => :string
  # # PROBLEM: changed ruby virtual_attribute to delegate
  # # attribute on a double relation (delegates to a delegate)
  # virtual_delegate :author_name, :to => :first_book, :prefix => true, :type => :string
  # # uses another virtual attribute that uses a relation
  # virtual_attribute :upper_first_book_author_name, :string, :arel => (lambda { |t| t[:first_book_author_name].upcase })
  # :uses points to a virtual_attribute that has a :uses with a hash
  # NOTE: Please do not change the :uses format here.
  #   This intentionally tests :uses with an array: [:bwmb, {:books => co_a}]
  #   vs a more condensed format: {:bwmb => {}, :books => co_a}
  # NOTE: no longer need this since uses has been deprecated
  has_many :famous_co_authors, :through => :book_with_most_bookmarks, :source => :co_authors

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
  # # this tests delegate
  # # this also tests an attribute :uses clause with a single symbol
  # virtual_delegate :name, :to => :author, :prefix => true, :type => :string
  # # this tests delegates to named child attribute
  # virtual_delegate :author_name2, :to => "author.name", :type => :string
  # # delegate to a polymorphic
  # virtual_delegate :description, :to => :current_photo, :prefix => true, :type => :string, :allow_nil => true

  # # simple uses to a virtual attribute (depends on author_name delegate)
  # virtual_attribute :upper_author_name, :string, :arel => (lambda { |t| t[:author_name].upcase } )
  # virtual_attribute :upper_author_name_def, :string, :arel => (lambda { |t| Arel::Nodes::NamedFunction.new("COALESCE", [t[:upper_author_name], "other"]) } )

  # def upper_author_name
  #   has_attribute?("upper_author_name") ? self["upper_author_name"] : author_name.upcase
  # end

  # def upper_author_name_def
  #   has_attribute?("upper_author_name_def") ? self["upper_author_name_def"] : upper_author_name || "other"
  # end
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

  virtual_total :total_special_books, :special_books
  virtual_total :total_special_books_published, :published_special_books
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
        # define_arel_attribute(:path_ids, :integer) do |t|
        #   materialized_path2_root_id_arel(t, pk, col)
        # end
        # TODO: materialized_path2_path_ids_arel
        # makes sense for postgres. may implement descendants. has_many with an array
        define_method(:path_ids) do
          self.class.materialized_path2_path_ids_ruby(send(col))
        end
      end

      if attr_list.include?(:root_id)
        define_arel_attribute(:root_id, :integer) do |t|
          materialized_path2_root_id_arel(t, pk, col)
        end

        define_method(:root_id) do
          self["root_id"] || self.class.calculate_materialized_path2_root_id_ruby(id, path_ids)
        end
      end

      if attr_list.include?(:parent_id)
        define_arel_attribute(:parent_id, :integer) do |t|
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
        define_arel_attribute(:child_path, :string) do |t|
          materialized_path2_child_path_arel(t, pk, col)
        end

        define_method(:child_path) do
          self["child_path"] || self.class.materialized_path2_child_path_ruby(id, send(col))
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
    end

    private

    def sql_fn(name, *args)
      Arel::Nodes::NamedFunction.new(name, args)
    end

    def sql_cast(expr, type)
      Arel::Nodes::NamedFunction.new("CAST", [Arel::Nodes::As.new(expr, Arel::Nodes::SqlLiteral.new(type))])
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
      Arel::Nodes::Concat.new(Arel::Nodes::Concat.new(t[ancestry_column], t[pk]), Arel.sql("'/'"))
    end

    def materialized_path2_child_path_ruby(id, ancestry)
      "#{ancestry}#{id}/"
    end

    # TODO: This is pg friendly (using an array) but probably not anything else
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
  include ArelAttribute::VirtualTotal
  include ArelAncestry

  arel_ancestry :path, prefix: false, attributes: true, associations: true

  # has_many :siblings, foreign_key: :parent_id, primary_key: :parent_id, class_name: "Person"
  has_many :siblings, foreign_key: :path, primary_key: :path, class_name: "Person"

  scope :roots, -> { where(path: "/") }

  def self.factory(count = 3, start: "a".ord)
    count.times.inject([]) do |ac, i|
      ac << create!(name: (start + i).chr, path: ac.last&.child_path || "/")
    end
  end
end
