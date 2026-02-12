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
      pending  "not working for sqlite yet" if Person.is_sqlite?
      results = Person.where(root_id: a.id.to_s).order(:id)
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
        expect(a.children.order(:id).to_a).to eq([b, d])
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
end
