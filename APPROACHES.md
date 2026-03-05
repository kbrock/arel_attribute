# Approaches for LIKE-based Associations

All branches solve the same problem: `has_many :descendants` and `has_many :ancestors`
using LIKE on a materialized path column, which doesn't fit Rails' FK=PK model.

Each branch must handle 4 contexts: JOIN (arel tables), preload batch (array of owners),
single-owner WHERE (one record), and Ruby-side bucketing (assigning preloaded records to owners).

All branch off master at `2f146f8`.

## Rails internals that need monkey-patching

Every approach must override some subset of these Rails methods:

- `Reflection#check_eager_loadable!` — allow non-standard scopes to eager-load
- `Reflection#join_scope` — build custom JOIN condition instead of FK=PK
- `AssociationScope#last_chain_scope` — skip standard FK=value WHERE for single-owner
- `Preloader::Association#loader_query` — custom batch loading (LIKE-based instead of FK IN (...))
- `Preloader::Association#load_records` — bucket preloaded records to owners (Ruby-side matching)
- `Association#reset` — clear cached scope when owner attributes change
- `Builder::HasMany.valid_options` — register new options (`:match`, `:join_strategy`)

The arity-2 branches (2, 3) dispatch on the first arg's type inside the lambda.
The strategy branch (1) dispatches by calling different methods on the strategy object.

## What the ancestry_spec.rb proves

All branches share essentially the same test suite proving:
- WHERE/ORDER/SELECT/DISTINCT on virtual attributes (`root_id`, `parent_id`, `child_path`)
- `belongs_to :root` (virtual FK), `belongs_to :parent` (virtual PK), `has_many :children`, `:siblings`
- `has_many :descendants` and `:ancestors` (LIKE-based) across all 4 contexts
- `virtual_total` counting descendants
- Create/build through association
- **Pending**: `subtree` (self + descendants)

## Strategy 1: strategy object — `pk_friendly_children1b`

**Strategy pattern via `join_strategy:` option.** Extracts a strategy Struct with 4 methods
(`join_arel`, `join_records`, `where_record`, `match?`), each handling one context explicitly.
Association definition is clean: `has_many :descendants, class_name: "Person", join_strategy: DescendantsStrategy.new(col, pk)`.

No type-checking dispatch inside lambdas. No synthetic FK column (`mid_path`). Strategy owns all join logic.

## Strategy 2: arity-2 lambda + synthetic FK — `pk_friendly_children2`

**Arity-2 lambda + synthetic `mid_path` FK.** The preload/single-record branches SELECT an extra
`mid_path` column (the owner's `child_path`) so Rails' standard FK bucketing works.
Uses `foreign_key: :mid_path, primary_key: :child_path` — no `match:` option needed.
Downside: injects a synthetic column into SELECT, coupling the lambda to Rails preloader internals.

This is the approach currently used by the ancestry gem.

## Strategy 3: arity-2 lambda + match: — `pk_friendly_children3`

**Arity-2 lambda + `match:` + Patch1/Patch2 structure.** Removes the synthetic `mid_path` FK —
uses `match:` for Ruby-side bucketing instead. The `match_association.rb` is organized into
two separable patches, each independently proposable to Rails:
- **Patch1** (keyed on `scope.arity == 2`): `check_eager_loadable!` + `join_scope` that calls `super` then merges lambda
- **Patch2** (keyed on `options[:match]`): suppresses FK=PK, custom `last_chain_scope`/`loader_query`/`load_records`, Ruby bucketing via `match:`

## Dropped branches

- **`pk_friendly_children`** — WIP predecessor to strategy 2. Superseded (missing `type_for_attribute` fix, Rails 7.2 compat, arg order swap).
- **`pk_friendly_children2b`** — Identical to the first commit of 1b and same models.rb as branch 3. Just a waypoint between strategy 2 and strategies 3/1.
