# frozen_string_literal: true

RSpec.describe ArelAttribute do
  describe ".define_arel_attribute" do
    it "registers the attribute" do
      expect(Author.arel_attribute?(:doubled)).to be true
      expect(Author.arel_attribute?(:upper_name)).to be true
    end

    it "does not register real columns" do
      expect(Author.arel_attribute?(:name)).to be false
    end

    it "lists virtual attribute names" do
      expect(Author.virtual_attribute_names).to include("doubled", "upper_name")
    end

    it "requires a block" do
      expect {
        Author.define_arel_attribute(:bad, :integer)
      }.to raise_error(ArgumentError, /arel block is required/)
    end
  end

  describe ".virtual_attribute (compatibility)" do
    it "registers via the arel option" do
      expect(Author.arel_attribute?(:nick_or_name)).to be true
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
end
