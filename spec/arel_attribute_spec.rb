# frozen_string_literal: true

RSpec.describe ArelAttribute, :with_test_class do
  before do
    TestClass.define_arel_attribute(:doubled, :integer) do |t|
      t[:col1] + t[:col1]
    end

    TestClass.define_arel_attribute(:upper_str, :string) do |t|
      Arel::Nodes::NamedFunction.new("UPPER", [t[:str]])
    end
  end

  describe ".define_arel_attribute" do
    it "registers the attribute" do
      expect(TestClass.arel_attribute?(:doubled)).to be true
      expect(TestClass.arel_attribute?(:upper_str)).to be true
    end

    it "does not register real columns" do
      expect(TestClass.arel_attribute?(:col1)).to be false
    end

    it "lists virtual attribute names" do
      expect(TestClass.virtual_attribute_names).to include("doubled", "upper_str")
    end

    it "requires a block" do
      expect {
        TestClass.define_arel_attribute(:bad, :integer)
      }.to raise_error(ArgumentError, /arel block is required/)
    end
  end

  describe ".virtual_attribute (compatibility)" do
    before do
      TestClass.virtual_attribute(:tripled, :integer, arel: ->(t) { t[:col1] + t[:col1] + t[:col1] })
    end

    it "registers via the arel option" do
      expect(TestClass.arel_attribute?(:tripled)).to be true
    end
  end

  describe "arel_table (TableProxy)" do
    it "returns an ArelAttribute node for virtual attributes" do
      node = TestClass.arel_table[:doubled]
      expect(node).to be_a(Arel::Nodes::ArelAttribute)
    end

    it "returns a standard Arel::Attribute for real columns" do
      node = TestClass.arel_table[:col1]
      expect(node).to be_a(Arel::Attributes::Attribute)
    end
  end

  describe "WHERE" do
    before do
      TestClass.create!(col1: 5, str: "hello")
      TestClass.create!(col1: 10, str: "world")
      TestClass.create!(col1: 3, str: "hello")
    end

    it "filters using the arel expression" do
      results = TestClass.where(doubled: 10)
      expect(results.map(&:col1)).to eq([5])
    end

    it "filters with string expressions" do
      results = TestClass.where(upper_str: "HELLO")
      expect(results.count).to eq(2)
    end

    it "combines virtual and real attribute filters" do
      results = TestClass.where(doubled: 10, str: "hello")
      expect(results.map(&:col1)).to eq([5])
    end

    it "works with explicit arel eq" do
      results = TestClass.where(TestClass.arel_table[:doubled].eq(10))
      expect(results.map(&:col1)).to eq([5])
    end

    it "works with arel gt" do
      results = TestClass.where(TestClass.arel_table[:doubled].gt(8)).order(:col1)
      expect(results.map(&:col1)).to eq([5, 10])
    end

    it "works with arel in" do
      results = TestClass.where(TestClass.arel_table[:doubled].in([6, 10])).order(:col1)
      expect(results.map(&:col1)).to eq([3, 5])
    end
  end

  describe "ORDER" do
    before do
      TestClass.create!(col1: 10, str: "b")
      TestClass.create!(col1: 5, str: "a")
      TestClass.create!(col1: 3, str: "c")
    end

    it "orders by the arel expression" do
      results = TestClass.order(:doubled)
      expect(results.map(&:col1)).to eq([3, 5, 10])
    end

    it "orders descending" do
      results = TestClass.order(doubled: :desc)
      expect(results.map(&:col1)).to eq([10, 5, 3])
    end

    it "orders by virtual then real column" do
      TestClass.create!(col1: 5, str: "z")
      results = TestClass.order(:doubled, :str)
      expect(results.map(&:str)).to eq(["c", "a", "z", "b"])
    end
  end

  describe "SELECT" do
    before do
      TestClass.create!(col1: 7, str: "test")
    end

    it "selects the arel expression as a named attribute" do
      result = TestClass.select(:doubled).first
      expect(result.doubled).to eq(14)
    end

    it "selects string arel expressions" do
      result = TestClass.select(:upper_str).first
      expect(result.upper_str).to eq("TEST")
    end

    it "selects multiple virtual attributes" do
      result = TestClass.select(:id, :doubled, :upper_str).first
      expect(result.doubled).to eq(14)
      expect(result.upper_str).to eq("TEST")
    end

    it "mixes virtual and real columns in select" do
      result = TestClass.select(:col1, :doubled, :str, :upper_str).first
      expect(result.col1).to eq(7)
      expect(result.doubled).to eq(14)
      expect(result.str).to eq("test")
      expect(result.upper_str).to eq("TEST")
    end
  end

  describe "chaining" do
    before do
      TestClass.create!(col1: 5, str: "hello")
      TestClass.create!(col1: 10, str: "world")
      TestClass.create!(col1: 3, str: "hello")
    end

    it "chains where and order on virtual attributes" do
      results = TestClass.where(upper_str: "HELLO").order(:doubled)
      expect(results.map(&:col1)).to eq([3, 5])
    end

    it "chains select, where, and order" do
      results = TestClass.select(:id, :doubled, :upper_str)
                         .where(upper_str: "HELLO")
                         .order(doubled: :desc)
      expect(results.map(&:doubled)).to eq([10, 6])
    end
  end

  describe "aliased table (self-join)" do
    it "preserves arel attribute lookup on aliased tables" do
      aliased = TestClass.arel_table.alias("test_classes_sub")
      node = aliased[:doubled]
      expect(node).to be_a(Arel::Nodes::ArelAttribute)
    end
  end
end
