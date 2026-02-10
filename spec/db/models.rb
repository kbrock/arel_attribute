class VirtualTotalTestBase < ActiveRecord::Base
  self.abstract_class = true
  self.belongs_to_required_by_default = false

  include ArelAttribute::Base
  include ArelAttribute::VirtualTotal
end

class Author < VirtualTotalTestBase
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

class Book < VirtualTotalTestBase
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

  def self.create_with_bookmarks(count)
    Author.create(:name => "foo").books.create!(:name => "book").tap { |book| book.create_bookmarks(count) }
  end

  def create_bookmarks(count, create_attrs = {})
    Array.new(count) do
      bookmarks.create({:name => "mark"}.merge(create_attrs))
    end
  end
end

class Bookmark < VirtualTotalTestBase
  belongs_to :book
end

class Photo < VirtualTotalTestBase
  belongs_to :imageable, :polymorphic => true
end

class Person < ActiveRecord::Base
  include ArelAttribute::Base
  include ArelAttribute::SqlDetection

  class << self
    private

    def sql_fn(name, *args)
      Arel::Nodes::NamedFunction.new(name, args)
    end

    def sql_cast(expr, type)
      Arel::Nodes::NamedFunction.new("CAST", [Arel.sql("#{expr.to_sql} AS #{type}")])
    end

    def sql_position(str, sub)
      is_pg? ? sql_fn("STRPOS", str, sub) : sql_fn("INSTR", str, sub)
    end

    def sql_case_root(path, root_val, not_root)
      Arel::Nodes::Case.new(path).when(Arel.sql("'/'")).then(root_val).else(not_root)
    end
  end

  # root_id: first id in the path, e.g. "/1/2/3/" => 1
  define_arel_attribute :root_id, :integer do |t|
    path = t[:path]
    stripped = sql_fn("LTRIM", path, Arel.sql("'/'"))
    len = sql_position(stripped, Arel.sql("'/'")) - 1
    segment = sql_fn("SUBSTR", path, 2, len)
    sql_case_root(path, t[:id], sql_cast(segment, "INTEGER"))
  end

  # parent_id: last id in the path, e.g. "/1/2/3/" => 3
  define_arel_attribute :parent_id, :integer do |t|
    path = t[:path]
    slash = Arel.sql("'/'")
    empty = Arel.sql("''")
    non_slash_chars = sql_fn("REPLACE", path, slash, empty)
    front = sql_fn("RTRIM", sql_fn("RTRIM", path, slash), non_slash_chars)
    last_segment = sql_fn("RTRIM", sql_fn("REPLACE", path, front, empty), slash)
    sql_case_root(path, Arel.sql("NULL"), sql_cast(last_segment, "INTEGER"))
  end

  # child_path: path children would have, e.g. id=2, path="/1/" => "/1/2/"
  define_arel_attribute :child_path, :string do |t|
    Arel::Nodes::Concat.new(
      Arel::Nodes::Concat.new(t[:path], t[:id]),
      Arel.sql("'/'")
    )
  end

  def root_id
    if has_attribute?("root_id")
      self["root_id"]
    else
      # NOTE: this is a special case
      ids = path_ids
      ids.empty? ? id : ids.first
    end
  end

  def parent_id
    if has_attribute?("parent_id")
      self["parent_id"]
    else
      # NOTE: this is different from root_id handling
      ids = path_ids
      ids.empty? ? nil : ids.last
    end
  end

  def child_path
    has_attribute?("child_path") ? self["child_path"] : "#{path}#{id}/"
  end

  belongs_to :root, foreign_key: :root_id, class_name: "Person", optional: true
  belongs_to :parent, foreign_key: :path, primary_key: :child_path, class_name: "Person",
                      inverse_of: :children, optional: true
  has_many :children, foreign_key: :path, primary_key: :child_path, class_name: "Person",
                      inverse_of: :parent
  has_many :siblings, foreign_key: :path, primary_key: :path, class_name: "Person"

  scope :roots, -> { where(path: "/") }

  def self.factory(count = 3, start: "a".ord)
    count.times.inject([]) do |ac, i|
      ac << create!(name: (start + i).chr, path: ac.last&.child_path || "/")
    end
  end

  private

  def path_ids
    return [] if path.blank? || path == "/"
    path[1..].split("/").map(&:to_i)
  end
end
