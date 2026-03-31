# frozen_string_literal: true

RSpec.describe "arel_attribute with through:" do
  describe "belongs_to delegate (Book -> Author)" do
    let!(:author) { Author.create!(name: "Alice") }
    let!(:book)   { Book.create!(name: "Ruby Guide", author: author) }
    let!(:orphan) { Book.create!(name: "Anonymous") }

    it "delegates to the association" do
      expect(book.author_name).to eq("Alice")
    end

    it "returns nil when association is nil" do
      expect(orphan.author_name).to be_nil
    end

    it "selects via SQL" do
      results = Book.select(:id, :author_name).order(:id).to_a
      expect { expect(results.map(&:author_name)).to eq(["Alice", nil]) }.to_not make_database_queries
    end

    it "filters in WHERE" do
      results = Book.where(author_name: "Alice")
      expect(results.map(&:name)).to eq(["Ruby Guide"])
    end

    it "orders by delegate" do
      Author.create!(name: "Bob").tap { |a| Book.create!(name: "Go Guide", author: a) }
      results = Book.where.not(author_id: nil).order(:author_name).pluck(:name)
      expect(results).to eq(["Ruby Guide", "Go Guide"])
    end

    it "registers as an arel attribute" do
      expect(Book.arel_attribute?(:author_name)).to be true
      expect(Book.arel_attribute_names).to include("author_name")
    end
  end

  describe "self-join delegate (Author -> teacher)" do
    let!(:grand)   { Author.create!(name: "Grand") }
    let!(:parent)  { Author.create!(name: "Parent", teacher: grand) }
    let!(:child1)  { Author.create!(name: "Child1", teacher: parent) }
    let!(:child2)  { Author.create!(name: "Child2", teacher: parent) }

    it "delegates to parent" do
      expect(child1.teacher_name).to eq("Parent")
    end

    it "returns nil for root" do
      expect(grand.teacher_name).to be_nil
    end

    it "selects via SQL" do
      results = Author.select(:id, :teacher_name).where(id: [child1.id, child2.id]).order(:id).to_a
      expect { expect(results.map(&:teacher_name)).to eq(["Parent", "Parent"]) }.to_not make_database_queries
    end

    it "filters in WHERE" do
      results = Author.where(teacher_name: "Parent")
      expect(results.map(&:name)).to match_array(["Child1", "Child2"])
    end

    it "uses table alias for self-join subquery" do
      sql = Author.select(:id, :teacher_name).to_sql
      expect(sql).to match(/authors_sub/i)
    end

    it "chains delegate to delegate (teacher_teacher_name)" do
      expect(child1.teacher_teacher_name).to eq("Grand")
      expect(parent.teacher_teacher_name).to be_nil
    end

    it "selects chained delegate via SQL" do
      results = Author.select(:id, :teacher_teacher_name).where(id: child1.id).to_a
      expect { expect(results.first.teacher_teacher_name).to eq("Grand") }.to_not make_database_queries
    end
  end

  describe "has_one polymorphic delegate (Author -> current_photo)" do
    let!(:author) { Author.create!(name: "Alice") }
    let!(:photo)  { Photo.create!(imageable: author, description: "headshot", purpose: "profile") }

    it "delegates to has_one" do
      expect(author.current_photo_description).to eq("headshot")
    end

    it "returns nil when no photo" do
      lonely = Author.create!(name: "Bob")
      expect(lonely.current_photo_description).to be_nil
    end

    it "selects via SQL" do
      results = Author.select(:id, :current_photo_description).where(id: author.id).to_a
      expect { expect(results.first.current_photo_description).to eq("headshot") }.to_not make_database_queries
    end

    it "adds polymorphic type constraint in SQL" do
      sql = Author.select(:id, :current_photo_description).to_sql
      expect(sql).to match(/imageable_type/i)
    end
  end

  describe "has_one with scope delegate (Author -> fancy_photo)" do
    let!(:author) { Author.create!(name: "Alice") }
    let!(:fancy)  { Photo.create!(imageable: author, description: "glamour", purpose: "fancy") }
    let!(:casual) { Photo.create!(imageable: author, description: "selfie", purpose: "casual") }

    it "delegates respecting scope" do
      expect(author.fancy_photo_description).to eq("glamour")
    end

    it "selects via SQL with scope applied" do
      results = Author.select(:id, :fancy_photo_description).where(id: author.id).to_a
      expect { expect(results.first.fancy_photo_description).to eq("glamour") }.to_not make_database_queries
    end
  end

  describe "has_one delegate (Author -> first_book)" do
    let!(:author) { Author.create!(name: "Alice") }
    let!(:book1)  { Book.create!(name: "First", author: author) }
    let!(:book2)  { Book.create!(name: "Second", author: author) }

    it "delegates to has_one" do
      expect(author.first_book_name).to eq("First")
    end

    it "selects via SQL" do
      results = Author.select(:id, :first_book_name).where(id: author.id).to_a
      expect { expect(results.first.first_book_name).to eq("First") }.to_not make_database_queries
    end

    it "delegates to a delegate (has_one -> belongs_to)" do
      expect(author.first_book_author_name).to eq("Alice")
    end

    it "selects chained delegate via SQL" do
      results = Author.select(:id, :first_book_author_name).where(id: author.id).to_a
      expect { expect(results.first.first_book_author_name).to eq("Alice") }.to_not make_database_queries
    end
  end

  describe "arel attribute building on a delegate" do
    let!(:author) { Author.create!(name: "Alice") }
    let!(:book)   { Book.create!(name: "Ruby Guide", author: author) }

    it "computes upper_author_name from delegate (ruby)" do
      expect(book.upper_author_name).to eq("ALICE")
    end

    it "selects upper_author_name via SQL" do
      results = Book.select(:id, :upper_author_name).where(id: book.id).to_a
      expect { expect(results.first.upper_author_name).to eq("ALICE") }.to_not make_database_queries
    end

    it "chains arel on arel on delegate (upper_author_name_def)" do
      orphan = Book.create!(name: "No Author")
      results = Book.select(:id, :upper_author_name_def).order(:id).to_a
      expect { expect(results.map(&:upper_author_name_def)).to eq(["ALICE", "other"]) }.to_not make_database_queries
    end

    it "computes upper_first_book_author_name from chained delegate (ruby)" do
      expect(author.upper_first_book_author_name).to eq("ALICE")
    end

    it "selects upper_first_book_author_name via SQL" do
      results = Author.select(:id, :upper_first_book_author_name).where(id: author.id).to_a
      expect { expect(results.first.upper_first_book_author_name).to eq("ALICE") }.to_not make_database_queries
    end
  end

  describe "has_one ordered by virtual attribute" do
    let!(:author) { Author.create!(name: "Alice") }
    let!(:book1)  { Book.create!(name: "Popular", author: author) }
    let!(:book2)  { Book.create!(name: "Niche", author: author) }

    before do
      3.times { Bookmark.create!(book: book1) }
      1.times { Bookmark.create!(book: book2) }
    end

    it "resolves has_one ordered by arel_total" do
      expect(author.book_with_most_bookmarks).to eq(book1)
    end

    it "generates SQL with subquery, not a raw column name" do
      rel = Book.where(:author_id => author.id).order(:total_bookmarks => :desc)
      expect(rel.to_sql).not_to include(%q{"total_bookmarks"})
      expect(rel.to_sql).to match(/SELECT COUNT/i)
    end

    it "uses subquery in association scope" do
      sql = author.association(:book_with_most_bookmarks).scope.to_sql
      expect(sql).not_to include(%q{"total_bookmarks"})
      expect(sql).to match(/ORDER BY/i)
    end
  end

  describe "has_many scoped by delegate (books_with_authors)" do
    let!(:author) { Author.create!(name: "Alice") }
    let!(:named)  { Book.create!(name: "Named", author: author) }
    let!(:anon)   { Book.create!(name: "Anon") }
    let!(:noname) { Book.create!(author: author) }

    it "filters using the delegate in the scope" do
      expect(author.books_with_authors.to_a).to eq([named])
    end
  end

  describe "error handling" do
    it "raises on unknown association" do
      expect {
        Author.arel_attribute(:bad_delegate, :string, through: :nonexistent, source: :name)
      }.to raise_error(ArgumentError, /unknown :through association/)
    end
  end
end
