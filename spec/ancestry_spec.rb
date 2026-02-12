# frozen_string_literal: true

RSpec.describe "Ancestry-style arel attributes" do
  let!(:people) { Person.factory(3) }
  let(:a) { people[0] }
  let(:b) { people[1] }
  let(:c) { people[2] }

  describe "arel registration" do
    it "registers arel attributes" do
      expect(Person.arel_attribute?("root_id")).to be true
      expect(Person.arel_attribute?("parent_id")).to be true
      expect(Person.arel_attribute?("child_path")).to be true
    end

    it "does not register real columns" do
      expect(Person.arel_attribute?("name")).to be false
      expect(Person.arel_attribute?("path")).to be false
    end
  end

  describe "Ruby getters" do
    it "computes path_ids from path" do
      expect(a.path_ids).to eq([])
      expect(b.path_ids).to eq([a.id])
      expect(c.path_ids).to eq([a.id, b.id])
    end

    it "computes root_id from path" do
      expect(a.root_id).to eq(a.id)
      expect(b.root_id).to eq(a.id)
      expect(c.root_id).to eq(a.id)
    end

    it "computes parent_id from path" do
      expect(a.parent_id).to be_nil
      expect(b.parent_id).to eq(a.id)
      expect(c.parent_id).to eq(b.id)
    end

    it "computes child_path from path and id" do
      expect(a.child_path).to eq("/#{a.id}/")
      expect(b.child_path).to eq("/#{a.id}/#{b.id}/")
      expect(c.child_path).to eq("/#{a.id}/#{b.id}/#{c.id}/")
    end
  end

  describe "WHERE with virtual attributes" do
    it "filters by root_id" do
      results = Person.where(root_id: a.id).order(:id)
      expect(results.map(&:id)).to eq([a.id, b.id, c.id])
    end

    it "filters by root_id with string value (type casting)" do
      results = Person.where(root_id: a.id.to_s).order(:id)
      # q_int = Person.where(root_id: a.id)
      # q_str = Person.where(root_id: a.id.to_s)
      # puts "INT SQL: #{q_int.to_sql}"
      # puts "STR SQL: #{q_str.to_sql}"
      expect(results.map(&:id)).to eq([a.id, b.id, c.id])
    end

    it "filters by root_id using string key" do
      results = Person.where("root_id" => a.id).order(:id)
      expect(results.map(&:id)).to eq([a.id, b.id, c.id])
    end

    it "filters by root_id using explicit arel" do
      results = Person.where(Person.arel_table[:root_id].eq(a.id)).order(:id)
      expect(results.map(&:id)).to eq([a.id, b.id, c.id])
    end

    it "filters by parent_id" do
      results = Person.where(parent_id: a.id).order(:id)
      expect(results.map(&:id)).to eq([b.id])
    end

    it "filters by parent_id using string key" do
      results = Person.where("parent_id" => a.id).order(:id)
      expect(results.map(&:id)).to eq([b.id])
    end

    it "filters by parent_id using explicit arel" do
      results = Person.where(Person.arel_table[:parent_id].eq(a.id)).order(:id)
      expect(results.map(&:id)).to eq([b.id])
    end
  end

  describe "ORDER with virtual attributes" do
    it "orders by parent_id with nulls (symbol)" do
      results = Person.where(id: [a.id, b.id, c.id]).order(:parent_id, :id)
      if Person.is_pg?
      # pg uses nulls_first standard
        expect(results.map(&:id)).to eq([b.id, c.id, a.id])
      else
        expect(results.map(&:id)).to eq([a.id, b.id, c.id])
      end
    end

    it "orders by parent_id with explicit arel and nulls_last" do
      sort = Arel::Nodes::Ascending.new(Person.arel_table[:parent_id]).nulls_last
      results = Person.where(id: [a.id, b.id, c.id]).order(sort, :id)
      expect(results.map(&:id)).to eq([b.id, c.id, a.id])
    end

    it "orders by root_id" do
      results = Person.where(id: [a.id, b.id, c.id]).order(:root_id, :id)
      expect(results.map(&:id)).to eq([a.id, b.id, c.id])
    end
  end

  describe "SELECT with virtual attributes" do
    it "selects root_id with alias" do
      results = Person.where(id: [a.id, b.id, c.id]).select(:id, :path, :root_id).order(:id).load
      expect(results.map(&:root_id)).to eq([a.id, a.id, a.id])
    end

    it "selects parent_id with alias" do
      results = Person.where(id: [a.id, b.id, c.id]).select(:id, :path, :parent_id).order(:id).load
      expect(results[0].parent_id).to be_nil
      expect(results[1].parent_id).to eq(a.id)
      expect(results[2].parent_id).to eq(b.id)
    end

    it "selects child_path with alias" do
      results = Person.where(id: [a.id, b.id, c.id]).select(:id, :path, :child_path).order(:id).load
      expect(results.map(&:child_path)).to eq([a.child_path, b.child_path, c.child_path])
    end

    it "selected values override Ruby getter" do
      result = Person.where(id: [a.id, b.id, c.id]).select(:id, :root_id).order(:id).first
      expect(result.has_attribute?("root_id")).to be true
      expect(result.root_id).to eq(a.id)
    end

    it "works with explicit arel and alias" do
      root_with_alias = Person.arel_table[:root_id].as("root_id")
      results = Person.where(id: [a.id, b.id, c.id]).select(:id, :name, root_with_alias).order(:id).load
      expect(results.map(&:root_id)).to eq([a.id, a.id, a.id])
    end
  end

  describe "DISTINCT with virtual attributes" do
    it "does not blow up with distinct order" do
      expect { Person.all.distinct.order(:root_id).load }.not_to raise_error
    end
  end

  describe "associations" do
    describe "belongs_to :root (virtual FK root_id)" do
      it "loads the root via the Ruby getter" do
        expect(c.root).to eq(a)
        expect(b.root).to eq(a)
        expect(a.root).to eq(a)
      end
    end

    describe "belongs_to :parent (real FK path, virtual PK child_path)" do
      it "loads the parent" do
        expect(a.parent).to be_nil
        expect(b.parent).to eq(a)
        expect(c.parent).to eq(b)
      end
    end

    describe "has_many :children (virtual PK child_path)" do
      it "loads children" do
        expect(a.children.order(:id).to_a).to eq([b])
        expect(b.children.order(:id).to_a).to eq([c])
        expect(c.children.order(:id).to_a).to be_empty
      end

      it "creates children via the association" do
        d = a.children.create!(name: "d")
        expect(d.path).to eq(a.child_path)
        expect(d.parent_id).to eq(a.id)
        expect(d.parent).to eq(a)
        expect(a.children.order(:id).to_a).to eq([b, d])
      end

      it "builds children via the association" do
        d = a.children.build(name: "d")
        expect(d.parent_id).to eq(a.id)
        expect(d.parent).to eq(a)
      end

      it "created child is findable by parent_id" do
        d = a.children.create!(name: "d")
        expect(Person.where(parent_id: a.id).order(:id).to_a).to eq([b, d])
      end
    end

    describe "has_many :siblings" do
      it "loads siblings (same path)" do
        d = Person.create!(name: "d", path: b.path)
        expect(b.siblings.order(:id).to_a).to include(b, d)
      end
    end
  end

  describe "preloading" do
    it "preloads root association" do
      people
      results = Person.where(id: [a.id, b.id, c.id]).preload(:root).order(:id).load
      expect(results.map { |p| p.root&.id }).to eq([a.id, a.id, a.id])
    end

    it "preloads parent association" do
      people
      results = Person.where(id: [a.id, b.id, c.id]).preload(:parent).order(:id).load
      expect(results.map { |p| p.parent&.id }).to eq([nil, a.id, b.id])
    end
  end

  describe "includes (eager load)" do
    it "includes root" do
      people
      results = Person.where(id: [a.id, b.id, c.id]).includes(:root).order(:id).load
      expect(results.map { |p| p.root&.id }).to eq([a.id, a.id, a.id])
    end

    it "includes parent" do
      people
      results = Person.where(id: [a.id, b.id, c.id]).includes(:parent).order(:id).load
      expect(results.map { |p| p.parent&.id }).to eq([nil, a.id, b.id])
    end
  end

  describe "joins" do
    it "joins children and filters" do
      b.update!(name: "mid")
      results = Person.joins(:children).where(children: { name: "mid" }).order(:id)
      expect(results.map(&:id)).to eq([a.id])
    end

    it "joins children and filters by virtual attribute" do
      results = Person.joins(:children).where(children: { root_id: a.id }).distinct.order(:id)
      expect(results.map(&:id)).to eq([a.id, b.id])
    end
  end

  describe "descendants (LIKE-based has_many)" do
    # descendants: all records whose path starts with our child_path
    # a (path="/") -> child_path="/1/" -> descendants: b (path="/1/"), c (path="/1/2/")
    # b (path="/1/") -> child_path="/1/2/" -> descendants: c (path="/1/2/")
    # c (path="/1/2/") -> child_path="/1/2/3/" -> descendants: none

    it "loads descendants" do
      expect(a.descendants.order(:id).to_a).to eq([b, c])
      expect(b.descendants.order(:id).to_a).to eq([c])
      expect(c.descendants.order(:id).to_a).to be_empty
    end

    it "loads descendants with deeper trees" do
      d = Person.create!(name: "d", path: c.child_path)
      expect(a.descendants.order(:id).to_a).to eq([b, c, d])
      expect(b.descendants.order(:id).to_a).to eq([c, d])
      expect(c.descendants.order(:id).to_a).to eq([d])
    end

    it "does not include self in descendants" do
      expect(a.descendants).not_to include(a)
    end
  end

  describe "ancestors (reverse LIKE has_many)" do
    # ancestors: records whose child_path is a prefix of our path
    # a (path="/") -> no ancestors (path_ids=[])
    # b (path="/1/") -> ancestors: a (a.child_path="/1/" is prefix of "/1/")
    # c (path="/1/2/") -> ancestors: a, b

    it "loads ancestors" do
      expect(a.ancestors.order(:id).to_a).to be_empty
      expect(b.ancestors.order(:id).to_a).to eq([a])
      expect(c.ancestors.order(:id).to_a).to eq([a, b])
    end

    it "loads ancestors with deeper trees" do
      d = Person.create!(name: "d", path: c.child_path)
      expect(d.ancestors.order(:id).to_a).to eq([a, b, c])
    end

    it "does not include self in ancestors" do
      expect(c.ancestors).not_to include(c)
    end
  end

  describe "subtree (self + descendants)", pending: "depends on descendants fix" do
    xit "includes self and all descendants" do
      expect(a.subtree.order(:id).to_a).to eq([a, b, c])
      expect(b.subtree.order(:id).to_a).to eq([b, c])
      expect(c.subtree.order(:id).to_a).to eq([c])
    end
  end

  describe "preloading descendants/ancestors" do
    it "preloads descendants for single owner" do
      results = Person.where(id: [a.id]).preload(:descendants).order(:id).load
      expect(results[0].descendants.map(&:id)).to match_array([b.id, c.id])
    end

    it "preloads descendants for multiple owners (same depth)" do
      d = a.children.create!(name: "d")
      results = Person.where(id: [b.id, d.id]).preload(:descendants).order(:id).load
      expect(results[0].descendants.map(&:id)).to match_array([c.id])
      expect(results[1].descendants.map(&:id)).to be_empty
    end

    it "preloads descendants for multiple owners (mixed depth)" do
      results = Person.where(id: [a.id, b.id, c.id]).preload(:descendants).order(:id).load
      expect(results[0].descendants.map(&:id)).to match_array([b.id, c.id])
      expect(results[1].descendants.map(&:id)).to match_array([c.id])
      expect(results[2].descendants.map(&:id)).to be_empty
    end

    it "preloads descendants with deeper trees" do
      d = Person.create!(name: "d", path: c.child_path)
      results = Person.where(id: [a.id, b.id]).preload(:descendants).order(:id).load
      expect(results[0].descendants.map(&:id)).to match_array([b.id, c.id, d.id])
      expect(results[1].descendants.map(&:id)).to match_array([c.id, d.id])
    end

    it "preloads descendants where leaf has no descendants" do
      results = Person.where(id: [c.id]).preload(:descendants).load
      expect(results[0].descendants.map(&:id)).to be_empty
    end

    it "preloads ancestors" do
      results = Person.where(id: [a.id, b.id, c.id]).preload(:ancestors).order(:id).load
      expect(results[0].ancestors.map(&:id)).to be_empty
      expect(results[1].ancestors.map(&:id)).to eq([a.id])
      expect(results[2].ancestors.map(&:id)).to match_array([a.id, b.id])
    end
  end

  describe "eager loading descendants/ancestors" do
    it "includes descendants" do
      results = Person.where(id: [a.id, b.id, c.id]).includes(:descendants).order(:id).load
      expect(results[0].descendants.map(&:id)).to match_array([b.id, c.id])
      expect(results[1].descendants.map(&:id)).to match_array([c.id])
      expect(results[2].descendants.map(&:id)).to be_empty
    end

    it "includes descendants for single owner" do
      results = Person.where(id: [a.id]).includes(:descendants).load
      expect(results[0].descendants.map(&:id)).to match_array([b.id, c.id])
    end

    it "includes ancestors" do
      results = Person.where(id: [a.id, b.id, c.id]).includes(:ancestors).order(:id).load
      expect(results[0].ancestors.map(&:id)).to be_empty
      expect(results[1].ancestors.map(&:id)).to eq([a.id])
      expect(results[2].ancestors.map(&:id)).to match_array([a.id, b.id])
    end
  end

  describe "joins with descendants/ancestors" do
    it "joins descendants and filters" do
      c.update!(name: "leaf")
      results = Person.joins(:descendants).where(descendants: { name: "leaf" }).distinct.order(:id)
      expect(results.map(&:id)).to eq([a.id, b.id])
    end

    it "joins ancestors and filters" do
      a.update!(name: "top")
      results = Person.joins(:ancestors).where(ancestors: { name: "top" }).distinct.order(:id)
      expect(results.map(&:id)).to eq([b.id, c.id])
    end
  end

  describe "virtual_total with descendants" do
    it "counts descendants via virtual_total" do
      results = Person.select(:id, :total_descendants).order(:id).load
      expect(results.map(&:total_descendants)).to eq([2, 1, 0])
    end
  end

  describe "create through association" do
    it "creates child with correct path" do
      d = a.children.create!(name: "d")
      expect(d.path).to eq(a.child_path)
      expect(d.parent).to eq(a)
    end

    it "created child appears in descendants of grandparent" do
      d = b.children.create!(name: "d")
      expect(d.path).to eq(b.child_path)
      expect(a.descendants.order(:id).to_a).to include(d)
    end
  end
end
