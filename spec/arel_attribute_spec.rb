# frozen_string_literal: true

RSpec.describe ArelAttribute do
  describe ".arel_attribute" do
    it "registers the attribute" do
      expect(Author.arel_attribute?(:doubled)).to be true
      expect(Author.arel_attribute?(:upper_name)).to be true
    end

    it "does not register real columns" do
      expect(Author.arel_attribute?(:name)).to be false
    end

    it "lists virtual attribute names" do
      expect(Author.arel_attribute_names).to include("doubled", "upper_name")
    end

    it "requires a block" do
      expect {
        Author.arel_attribute(:bad, :integer)
      }.to raise_error(ArgumentError, /arel block is required/)
    end
  end


  describe "arel_table (TableProxy)" do
    it "returns an ArelAttribute node for virtual attributes" do
      node = Author.arel_table[:doubled]
      expect(node).to be_a(Arel::Nodes::ArelAttribute)
    end

    it "returns a standard Arel::Attribute for real columns" do
      node = Author.arel_table[:name]
      expect(node).to be_a(Arel::Attributes::Attribute)
    end
  end

  describe "WHERE" do
    before do
      Author.create!(teacher_id: 5, name: "hello")
      Author.create!(teacher_id: 10, name: "world")
      Author.create!(teacher_id: 3, name: "hello")
    end

    it "filters using the arel expression" do
      results = Author.where(doubled: 10)
      expect(results.map(&:teacher_id)).to eq([5])
    end

    it "filters with string expressions" do
      results = Author.where(upper_name: "HELLO")
      expect(results.count).to eq(2)
    end

    it "combines virtual and real attribute filters" do
      results = Author.where(doubled: 10, name: "hello")
      expect(results.map(&:teacher_id)).to eq([5])
    end

    it "works with explicit arel eq" do
      results = Author.where(Author.arel_table[:doubled].eq(10))
      expect(results.map(&:teacher_id)).to eq([5])
    end

    it "works with arel gt" do
      results = Author.where(Author.arel_table[:doubled].gt(8)).order(:teacher_id)
      expect(results.map(&:teacher_id)).to eq([5, 10])
    end

    it "works with arel in" do
      results = Author.where(Author.arel_table[:doubled].in([6, 10])).order(:teacher_id)
      expect(results.map(&:teacher_id)).to eq([3, 5])
    end
  end

  describe "ORDER" do
    before do
      Author.create!(teacher_id: 10, name: "b")
      Author.create!(teacher_id: 5, name: "a")
      Author.create!(teacher_id: 3, name: "c")
    end

    it "orders by the arel expression" do
      results = Author.order(:doubled)
      expect(results.map(&:teacher_id)).to eq([3, 5, 10])
    end

    it "orders descending" do
      results = Author.order(doubled: :desc)
      expect(results.map(&:teacher_id)).to eq([10, 5, 3])
    end

    it "orders by virtual then real column" do
      Author.create!(teacher_id: 5, name: "z")
      results = Author.order(:doubled, :name)
      expect(results.map(&:name)).to eq(["c", "a", "z", "b"])
    end

    # Edge case: VA arel contains ORDER BY ... DESC LIMIT 1 subquery.
    # Rails < 8.1 DISTINCT handler strips DESC, corrupting the subquery result.
    describe "with VA containing DESC subquery" do
      let!(:with_photos) { Author.create!(name: "photo_author").tap { |a| 3.times { a.photos.create! } } }
      let!(:without_photos) { Author.create!(name: "no_photo_author") }

      before do
        pending "Rails < 8.1 DISTINCT handler strips DESC from subquery expressions" if ActiveRecord.version < Gem::Version.new("8.1")
      end

      it "selects a VA with internal DESC" do
        ids = [with_photos.id, without_photos.id]
        results = Author.where(id: ids).select(:id, :current_photo_id).order(:id).load
        photo_ids = results.map(&:current_photo_id)
        expect(photo_ids[0]).to be_a(Integer)
        expect(photo_ids[1]).to be_nil
      end

      it "orders by a VA with internal DESC" do
        ids = [with_photos.id, without_photos.id]
        results = Author.where(id: ids).select(:id, :current_photo_id).order(:current_photo_id).load
        expect(results.map(&:current_photo_id)).to all(be_a(Integer).or(be_nil))
      end

      it "orders by a VA with internal DESC (not in select)" do
        ids = [with_photos.id, without_photos.id]
        results = Author.where(id: ids).select(:id, :name).order(:current_photo_id).load
        expect(results.size).to eq(2)
      end

      it "orders by a VA with internal DESC (no select)" do
        ids = [with_photos.id, without_photos.id]
        results = Author.where(id: ids).order(:current_photo_id).load
        expect(results.size).to eq(2)
      end
    end
  end

  # Edge case: DISTINCT forces ORDER columns into SELECT, which can corrupt
  # complex VA expressions. Fixed in Rails 8.1.
  describe "DISTINCT with virtual attributes" do
    before do
      pending "Rails < 8.1 DISTINCT handler strips DESC from subquery expressions" if ActiveRecord.version < Gem::Version.new("8.1")
      Author.create!(name: "a").tap { |a| 3.times { a.photos.create! } }
      Author.create!(name: "b").tap { |b| 2.times { b.photos.create! } }
      Author.create!(name: "c")
    end

    it "distinct + order by VA with DESC inside" do
      expect { Author.all.distinct.order(:current_photo_id).load }.not_to raise_error
    end

    it "distinct + select + order by VA with DESC inside" do
      expect { Author.all.select(:id, :current_photo_id).distinct.order(:current_photo_id).load }.not_to raise_error
    end
  end

  describe "SELECT" do
    before do
      Author.create!(teacher_id: 7, name: "test")
    end

    it "selects the arel expression as a named attribute" do
      result = Author.select(:doubled).first
      expect(result.doubled).to eq(14)
    end

    it "selects string arel expressions" do
      result = Author.select(:upper_name).first
      expect(result.upper_name).to eq("TEST")
    end

    it "selects multiple virtual attributes" do
      result = Author.select(:id, :doubled, :upper_name).first
      expect(result.doubled).to eq(14)
      expect(result.upper_name).to eq("TEST")
    end

    it "mixes virtual and real columns in select" do
      result = Author.select(:teacher_id, :doubled, :name, :upper_name).first
      expect(result.teacher_id).to eq(7)
      expect(result.doubled).to eq(14)
      expect(result.name).to eq("test")
      expect(result.upper_name).to eq("TEST")
    end
  end

  describe "chaining" do
    before do
      Author.create!(teacher_id: 5, name: "hello")
      Author.create!(teacher_id: 10, name: "world")
      Author.create!(teacher_id: 3, name: "hello")
    end

    it "chains where and order on virtual attributes" do
      results = Author.where(upper_name: "HELLO").order(:doubled)
      expect(results.map(&:teacher_id)).to eq([3, 5])
    end

    it "chains select, where, and order" do
      results = Author.select(:id, :doubled, :upper_name)
        .where(upper_name: "HELLO")
        .order(doubled: :desc)
      expect(results.map(&:doubled)).to eq([10, 6])
    end
  end

  describe "aliased table (self-join)" do
    it "preserves arel attribute lookup on aliased tables" do
      aliased = Author.arel_table.alias("authors_sub")
      node = aliased[:doubled]
      expect(node).to be_a(Arel::Nodes::ArelAttribute)
    end
  end

  describe "virtual attribute read/write" do
    # Person has a virtual parent_id arel attribute (not a real column).
    # belongs_to :parent uses parent_id as the foreign key.
    # These tests verify that _read_attribute, _write_attribute, and
    # write_attribute correctly store/retrieve values for virtual arel
    # attributes, which is critical for association FK handling.

    let!(:people) { Person.factory(3) }
    let(:a) { people[0] }
    let(:b) { people[1] }

    describe "_write_attribute / _read_attribute" do
      it "stores and retrieves a virtual arel attribute value" do
        person = Person.new(name: "test")
        person._write_attribute("parent_id", a.id)
        expect(person._read_attribute("parent_id")).to eq(a.id)
      end

      it "does not interfere with real column attributes" do
        person = Person.new(name: "test")
        person._write_attribute("name", "changed")
        expect(person._read_attribute("name")).to eq("changed")
      end
    end

    describe "belongs_to with virtual FK" do
      # belongs_to :parent uses parent_id (a virtual arel attribute) as the
      # foreign key. BelongsToAssociation#replace_keys calls owner[fk]= which
      # routes through write_attribute. Without the write_attribute override,
      # this raises MissingAttributeError because parent_id isn't a real column.

      # Needed for associations: write_attribute must store the virtual FK
      # so _read_attribute (used by AR internals) can find it.
      it "write_attribute stores virtual FK for _read_attribute" do
        person = Person.new(name: "test", path: "/")
        person[:parent_id] = a.id
        expect(person._read_attribute("parent_id")).to eq(a.id)
      end

      it "assigning parent resolves back to the same record" do
        person = Person.new(name: "test", path: "/")
        person.parent = a
        expect(person.parent).to eq(a)
      end

      it "building child through has_many resolves parent" do
        child = a.children.build(name: "child")
        expect(child.parent).to eq(a)
      end

      it "creating child through has_many persists correctly" do
        child = a.children.create!(name: "child")
        expect(child.reload.parent).to eq(a)
      end

      it "does not interfere with real column assignments" do
        person = Person.new
        person.write_attribute(:name, "hello")
        expect(person.name).to eq("hello")
      end
    end
  end

  describe "query efficiency" do
    let!(:with_photos) { Author.create!(name: "photo_author", teacher_id: 5).tap { |a| 3.times { a.photos.create! } } }
    let!(:without_photos) { Author.create!(name: "no_photo_author", teacher_id: 10) }

    it "resolves basic arel attributes in a single query" do
      query = Author.select(:id, :doubled, :upper_name).order(:id).load
      expect do
        expect(query.map(&:doubled)).to eq([10, 20])
        expect(query.map(&:upper_name)).to eq(%w[PHOTO_AUTHOR NO_PHOTO_AUTHOR])
      end.not_to make_database_queries
    end

    it "resolves subquery arel attributes in a single query" do
      query = Author.select(:id, :current_photo_id).order(:id).load
      expect do
        expect(query.first.current_photo_id).to be_a(Integer)
        expect(query.last.current_photo_id).to be_nil
      end.not_to make_database_queries
    end

    it "ruby fallback for current_photo_id triggers a query" do
      author = Author.find(with_photos.id)
      expect do
        expect(author.current_photo_id).to be_a(Integer)
      end.to make_database_queries(:count => 1)
    end
  end
end
