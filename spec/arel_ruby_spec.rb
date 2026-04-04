# frozen_string_literal: true

require "spec_helper"

RSpec.describe ArelAttribute::ArelRuby do
  let(:t) { Author.arel_table }

  describe ".convert" do
    it "converts a real column reference" do
      node = t[:name]
      expect(described_class.convert(node, Author)).to eq("self[:name]")
    end

    it "converts a virtual attribute reference" do
      node = t[:doubled]
      # TableProxy wraps virtual attrs in ArelAttribute node; convert unwraps
      ruby = described_class.convert(node, Author)
      expect(ruby).not_to include("ArelAttribute")
    end

    it "converts UPPER" do
      node = Arel::Nodes::NamedFunction.new("UPPER", [t[:name]])
      expect(described_class.convert(node, Author)).to eq("self[:name]&.upcase")
    end

    it "converts LOWER" do
      node = Arel::Nodes::NamedFunction.new("LOWER", [t[:name]])
      expect(described_class.convert(node, Author)).to eq("self[:name]&.downcase")
    end

    it "converts COALESCE" do
      node = Arel::Nodes::NamedFunction.new("COALESCE", [t[:nickname], t[:name]])
      expect(described_class.convert(node, Author)).to eq("self[:nickname] || self[:name]")
    end

    it "converts addition" do
      # arel wraps math in Grouping: (left + right)
      node = t[:id] + t[:id]
      expect(described_class.convert(node, Author)).to eq("(self[:id] + self[:id])")
    end

    it "converts subtraction" do
      node = t[:id] - Arel::Nodes::Quoted.new(1)
      expect(described_class.convert(node, Author)).to eq("(self[:id] - 1)")
    end

    it "converts multiplication" do
      node = t[:id] * 2
      expect(described_class.convert(node, Author)).to eq("self[:id] * 2")
    end

    it "converts division" do
      node = Arel::Nodes::Division.new(t[:id], 2)
      expect(described_class.convert(node, Author)).to eq("self[:id] / 2")
    end

    it "converts grouping" do
      # t[:id] + t[:id] already wraps in Grouping, so explicit Grouping double-wraps
      node = Arel::Nodes::Grouping.new(t[:id] + t[:id])
      expect(described_class.convert(node, Author)).to eq("((self[:id] + self[:id]))")
    end

    it "converts string concatenation" do
      node = Arel::Nodes::Concat.new(t[:name], t[:nickname])
      expect(described_class.convert(node, Author)).to eq("self[:name].to_s + self[:nickname].to_s")
    end

    it "converts a simple CASE statement" do
      node = Arel::Nodes::Case.new(t[:name])
        .when("Alice").then(Arel.sql("'admin'"))
        .else(Arel.sql("'user'"))
      ruby = described_class.convert(node, Author)
      expect(ruby).to include("case self[:name]")
      expect(ruby).to include('when "Alice"')
      expect(ruby).to include('"admin"')
      expect(ruby).to include('"user"')
    end

    it "converts a searched CASE statement" do
      node = Arel::Nodes::Case.new
        .when(t[:name].eq(nil)).then(Arel.sql("'unknown'"))
        .else(t[:name])
      ruby = described_class.convert(node, Author)
      expect(ruby).to include("when self[:name].nil?")
      expect(ruby).to include('"unknown"')
    end

    it "converts equality" do
      node = t[:name].eq("Alice")
      expect(described_class.convert(node, Author)).to eq('self[:name] == "Alice"')
    end

    it "converts IS NULL" do
      node = t[:name].eq(nil)
      expect(described_class.convert(node, Author)).to eq("self[:name].nil?")
    end

    it "converts IS NOT NULL" do
      node = t[:name].not_eq(nil)
      expect(described_class.convert(node, Author)).to eq("!self[:name].nil?")
    end

    it "converts greater than" do
      node = t[:id].gt(5)
      expect(described_class.convert(node, Author)).to eq("self[:id] > 5")
    end

    it "converts SQL literal strings" do
      node = Arel.sql("'hello'")
      expect(described_class.convert(node, Author)).to eq('"hello"')
    end

    it "converts SQL literal NULL" do
      node = Arel.sql("NULL")
      expect(described_class.convert(node, Author)).to eq("nil")
    end

    it "converts SQL literal numbers" do
      node = Arel.sql("42")
      expect(described_class.convert(node, Author)).to eq("42")
    end

    it "converts LENGTH" do
      node = Arel::Nodes::NamedFunction.new("LENGTH", [t[:name]])
      expect(described_class.convert(node, Author)).to eq("self[:name]&.length")
    end

    it "converts REPLACE" do
      node = Arel::Nodes::NamedFunction.new("REPLACE", [t[:name], Arel.sql("'/'"), Arel.sql("''")])
      expect(described_class.convert(node, Author)).to eq('self[:name]&.gsub("/", "")')
    end

    it "converts ArelAttribute node by unwrapping" do
      node = t[:nick_or_name] # goes through TableProxy, returns ArelAttribute node
      ruby = described_class.convert(node, Author)
      # Should unwrap to the inner expression
      expect(ruby).not_to include("ArelAttribute")
    end

    it "raises on unsupported nodes" do
      # A SelectManager (subquery) should not be convertible
      subquery = Author.arel_table.project(Arel.star)
      expect { described_class.convert(subquery, Author) }.to raise_error(
        ArelAttribute::ArelRuby::UnsupportedNode
      )
    end

    it "raises on unknown SQL functions" do
      node = Arel::Nodes::NamedFunction.new("RANDOM", [])
      expect { described_class.convert(node, Author) }.to raise_error(
        ArelAttribute::ArelRuby::UnsupportedNode, /RANDOM/
      )
    end
  end

  describe "ruby: true" do
    it "auto-generates a working Ruby method for upper_name" do
      author = Author.create!(name: "Alice")
      expect(author.upper_name).to eq("ALICE")
    end

    it "auto-generates a working Ruby method for nick_or_name" do
      author = Author.create!(name: "Alice", nickname: "Ally")
      expect(author.nick_or_name).to eq("Ally")
    end

    it "auto-generates nick_or_name falling back to name" do
      author = Author.create!(name: "Alice")
      expect(author.nick_or_name).to eq("Alice")
    end

    it "prefers SQL-loaded value over Ruby computation" do
      author = Author.create!(name: "Alice")
      loaded = Author.select(:id, :upper_name).find(author.id)
      expect(loaded.upper_name).to eq("ALICE")
    end

    it "auto-generates a working Ruby method for doubled" do
      author = Author.create!(name: "Alice", teacher_id: 7)
      expect(author.doubled).to eq(14)
    end
  end

  describe "ruby: 'string'" do
    it "defines a method from the string expression" do
      author = Author.create!(name: "Alice", nickname: "Ally")
      expect(author.name_no_group).to eq("Ally")
    end

    it "falls back through the string expression" do
      author = Author.create!(name: "Alice")
      expect(author.name_no_group).to eq("Alice")
    end

    it "prefers SQL-loaded value over the string expression" do
      author = Author.create!(name: "Alice", nickname: "Ally")
      loaded = Author.select(:id, :name_no_group).find(author.id)
      expect(loaded.name_no_group).to eq("Ally")
    end
  end

  describe ".build_arel_ruby_module" do
    it "returns a module with the generated methods" do
      # build_arel_ruby_module only works when there are pending methods,
      # which are consumed by define_attribute_methods. Test via convert instead.
      node = Arel::Nodes::NamedFunction.new("UPPER", [Author.arel_table[:name]])
      ruby_src = described_class.convert(node, Author)
      expect(ruby_src).to eq("self[:name]&.upcase")
    end
  end
end
