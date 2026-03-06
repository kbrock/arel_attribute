# arel_attribute

Ruby gem that provides arel-backed virtual attributes for ActiveRecord models.

## Running tests

```bash
source /opt/homebrew/share/chruby/chruby.sh && chruby 4.0 && bundle install   # first time only
source /opt/homebrew/share/chruby/chruby.sh && chruby 4.0 && bundle exec rspec                          # all tests
source /opt/homebrew/share/chruby/chruby.sh && chruby 4.0 && bundle exec rspec -e "description"         # single test
source /opt/homebrew/share/chruby/chruby.sh && chruby 4.0 && bundle exec rspec spec/ancestry_spec.rb    # ancestry tests only
```

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
