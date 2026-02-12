# arel_attribute

Ruby gem that provides arel-backed virtual attributes for ActiveRecord models.

## Running tests

```bash
source /opt/homebrew/share/chruby/chruby.sh && chruby 4.0 && bundle install   # first time only
source /opt/homebrew/share/chruby/chruby.sh && chruby 4.0 && bundle exec rspec                          # all tests
source /opt/homebrew/share/chruby/chruby.sh && chruby 4.0 && bundle exec rspec -e "description"         # single test
source /opt/homebrew/share/chruby/chruby.sh && chruby 4.0 && bundle exec rspec spec/ancestry_spec.rb    # ancestry tests only
```

**Current status: 148 passing, 1 pending (`subtree` — intentionally `xit`).**

## Database adapters

Default is sqlite3. Set `DB` env var to switch:
- `DB=sqlite3` (default)
- `DB=postgresql` or `DB=pg`
- `DB=mysql2` or `DB=mysql`

## Debugging

- **Always write tests** — do NOT use `ruby -e` one-off scripts. The test environment
  sets up models and databases correctly; standalone scripts fail with anonymous class errors.
- Use `bundle exec rspec -e "description"` to run a specific test.
- For Rails monkey-patches in `match_association.rb` and `arel_attribute.rb`:
  - Put the Rails version and source file:line in a comment above each overridden method
  - Wrap changes in `# CHANGED` / `# / CHANGED` blocks with the original line commented out
  - This makes it easy to diff against upstream Rails when upgrading

## Architecture

- `ArelAttribute::Base` — included into ActiveRecord models, provides `arel_attribute`
- `ArelAttribute::TableProxy` — wraps `Arel::Table` to resolve virtual attributes via arel blocks in WHERE/ORDER/SELECT
- `ArelAttribute::ArelAggregate` — aggregate arel attributes (`arel_total`, `arel_sum`, etc.) using correlated subqueries
- `Arel::Nodes::ArelAttribute` — custom arel node that expands arel blocks at SQL generation time
- `ArelAttribute::MatchAssociation` — 4 Rails monkey-patches enabling arity-2 scope lambdas on associations

## Arity-2 association lambdas

The core innovation for LIKE-based associations (descendants, ancestors). A scope with arity 2 receives `(owner_or_table, foreign_table)`:

- **Join context**: both args are arel tables — pure arel SQL, no PK needed
- **Preload batch**: `owner_or_table` is an Array of owner records — JOIN to owners alias, SELECT synthetic `mid_path` column for preloader matching
- **Single owner**: `owner_or_table` is a record — inline SQL WHERE

Rails monkey-patches needed:
1. `HasManyReflection#check_eager_loadable!` — allow arity-2 scopes for eager loading
2. `AbstractReflection#join_scope` — call arity-2 scope with `(owner_table, target_table)` instead of FK=PK
3. `AssociationScope#last_chain_scope` — skip standard FK=value WHERE for arity-2 scopes
4. `Preloader::Association#loader_query` — use `Arity2LoaderQuery` which calls scope with owners array

## The blocking design problem

**3-branch lambdas + synthetic `mid_path`** are the main wart preventing a clean public API:

- The preloader needs `record[fk] == owner[pk]` equality to match loaded records back to owners
- LIKE-based associations have no natural FK for this — solution is a synthetic `mid_path` column (SELECT'd in the batch preload branch) that equals the owner's path value
- This works and all tests pass, but the 3-branch pattern with `mid_path` is too much conceptual overhead to ship as a public API
- The single-owner branch is conceptually redundant (just a batch of 1), but Rails calls the lambda differently so it must be handled separately

**What would fix it:** a custom matching hook in the Rails preloader — "here's how to match records to owners" — instead of assuming `record[fk] == owner[pk]`. That would eliminate `mid_path` and collapse to 2 branches (arel tables vs ruby records).

See `PROBLEM_ANALYSIS.md` for full analysis of approaches explored and rejected.

## What the ancestry_spec.rb proves

`spec/ancestry_spec.rb` is the proof-of-concept test suite using a `Person` model with a `path` column (materialized_path2 format). It covers:

- WHERE/ORDER/SELECT/DISTINCT on virtual attributes (`root_id`, `parent_id`, `child_path`)
- `belongs_to :root` (virtual FK `root_id`)
- `belongs_to :parent` (real FK `path`, virtual PK `child_path`)
- `has_many :children` (virtual PK `child_path`)
- `has_many :siblings`
- `has_many :descendants` (LIKE-based arity-2 lambda)
- `has_many :ancestors` (reverse LIKE arity-2 lambda)
- Preload, includes (eager load), joins for all associations
- `virtual_total` counting descendants
- Create/build through association (sets `path` from parent)
- **Pending**: `subtree` (self + descendants) — depends on a descendants fix
