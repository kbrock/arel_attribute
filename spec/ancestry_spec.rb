# frozen_string_literal: true

RSpec.describe "Ancestry-style arel attributes", :with_test_class do
  # Ancestry uses a path column like "/1/2/3/" to represent hierarchy.
  # We derive root_id, parent_id, and child_path from the path via SQL.

  before do
    ActiveRecord::Schema.define do
      self.verbose = false
      create_table :people, force: true do |t|
        t.string :path, null: false, default: "/"
        t.string :name
      end
    end

    # rubocop:disable Lint/ConstantDefinitionInBlock
    class Person < ActiveRecord::Base
      include ArelAttribute::Base
      include ArelAttribute::SqlDetection

      class << self
        private

        # Arel helper: SQL function node
        def sql_fn(name, *args)
          Arel::Nodes::NamedFunction.new(name, args)
        end

        # Arel helper: CAST(expr AS type)
        def sql_cast(expr, type)
          Arel::Nodes::NamedFunction.new("CAST", [Arel.sql("#{expr.to_sql} AS #{type}")])
        end

        def sql_position(str, sub)
          if is_pg?
            sql_fn("STRPOS", str, sub)
          else
            sql_fn("INSTR", str, sub)
          end
        end
        # Arel helper: CASE WHEN path = '/' THEN root_val ELSE not_root END
        def sql_case_root(path, root_val, not_root)
          Arel::Nodes::Case.new(path).when(Arel.sql("'/'")).then(root_val).else(not_root)
        end
      end

      # root_id: first id in the path, e.g. "/1/2/3/" => 1
      # For root nodes (path="/"), root_id is the node's own id.
      #
      # SQL: CASE path WHEN '/' THEN id ELSE CAST(SUBSTR(path, 2, INSTR(LTRIM(path, '/'), '/') - 1) AS INTEGER) END
      define_arel_attribute :root_id, :integer do |t|
        path = t[:path]
        stripped = sql_fn("LTRIM", path, Arel.sql("'/'"))
        len = sql_position(stripped, Arel.sql("'/'")) - 1
        segment = sql_fn("SUBSTR", path, 2, len)
        sql_case_root(path, t[:id], sql_cast(segment, "INTEGER"))
      end

      # parent_id: last id in the path, e.g. "/1/2/3/" => 3 (i.e. parent of this node)
      # For root nodes (path="/"), parent_id is NULL.
      #
      # SQL: CASE path WHEN '/' THEN NULL ELSE CAST(RTRIM(REPLACE(path, RTRIM(RTRIM(path, '/'), REPLACE(path, '/', '')), ''), '/') AS INTEGER) END
      define_arel_attribute :parent_id, :integer do |t|
        path = t[:path]
        slash = Arel.sql("'/'")
        empty = Arel.sql("''")
        non_slash_chars = sql_fn("REPLACE", path, slash, empty)
        front = sql_fn("RTRIM", sql_fn("RTRIM", path, slash), non_slash_chars)
        last_segment = sql_fn("RTRIM", sql_fn("REPLACE", path, front, empty), slash)
        sql_case_root(path, Arel.sql("NULL"), sql_cast(last_segment, "INTEGER"))
      end

      # child_path: path that children of this node would have, e.g. id=2, path="/1/" => "/1/2/"
      # SQL: path || id || '/'
      define_arel_attribute :child_path, :string do |t|
        Arel::Nodes::Concat.new(
          Arel::Nodes::Concat.new(t[:path], t[:id]),
          Arel.sql("'/'")
        )
      end

      # Ruby getters with has_attribute? pattern
      def root_id
        if has_attribute?("root_id")
          self["root_id"]
        else
          ids = path_ids
          ids.empty? ? id : ids.first
        end
      end

      def parent_id
        if has_attribute?("parent_id")
          self["parent_id"]
        else
          ids = path_ids
          ids.empty? ? nil : ids.last
        end
      end

      def child_path
        if has_attribute?("child_path")
          self["child_path"]
        else
          "#{path}#{id}/"
        end
      end

      # Association definitions using virtual foreign keys
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
    # rubocop:enable Lint/ConstantDefinitionInBlock
  end

  after do
    Object.send(:remove_const, :Person)
  end

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

    it "filters by root_id with string value (type casting)", pending: "type casting not yet implemented for arel attributes" do
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
      # SQLite puts NULLs first by default
      results = Person.order(:parent_id, :id)
      expect(results.map(&:id)).to eq([a.id, b.id, c.id])
    end

    it "orders by parent_id with explicit arel and nulls_last" do
      sort = Arel::Nodes::Ascending.new(Person.arel_table[:parent_id]).nulls_last
      results = Person.order(sort, :id)
      expect(results.map(&:id)).to eq([b.id, c.id, a.id])
    end

    it "orders by root_id" do
      results = Person.order(:root_id, :id)
      expect(results.map(&:id)).to eq([a.id, b.id, c.id])
    end
  end

  describe "SELECT with virtual attributes" do
    it "selects root_id with alias" do
      results = Person.select(:id, :path, :root_id).order(:id).load
      expect(results.map(&:root_id)).to eq([a.id, a.id, a.id])
    end

    it "selects parent_id with alias" do
      results = Person.select(:id, :path, :parent_id).order(:id).load
      expect(results[0].parent_id).to be_nil
      expect(results[1].parent_id).to eq(a.id)
      expect(results[2].parent_id).to eq(b.id)
    end

    it "selects child_path with alias" do
      results = Person.select(:id, :path, :child_path).order(:id).load
      expect(results.map(&:child_path)).to eq([a.child_path, b.child_path, c.child_path])
    end

    it "selected values override Ruby getter" do
      result = Person.select(:id, :root_id).order(:id).first
      # has_attribute? returns true, so the SQL-computed value is used
      expect(result.has_attribute?("root_id")).to be true
      expect(result.root_id).to eq(a.id)
    end

    it "works with explicit arel and alias" do
      root_with_alias = Person.arel_table[:root_id].as("root_id")
      results = Person.select(:id, :name, root_with_alias).order(:id).load
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
      results = Person.preload(:root).order(:id).load
      expect(results.map { |p| p.root&.id }).to eq([a.id, a.id, a.id])
    end

    it "preloads parent association" do
      people
      results = Person.preload(:parent).order(:id).load
      expect(results.map { |p| p.parent&.id }).to eq([nil, a.id, b.id])
    end
  end

  describe "includes (eager load)" do
    it "includes root" do
      people
      results = Person.includes(:root).order(:id).load
      expect(results.map { |p| p.root&.id }).to eq([a.id, a.id, a.id])
    end

    it "includes parent" do
      people
      results = Person.includes(:parent).order(:id).load
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
