# arel_attribute

Ruby gem that provides arel-backed virtual attributes for ActiveRecord models.

## Running tests

```bash
bundle exec rspec                          # all tests
```

## Database adapters

Default is sqlite3. Set `DB` env var to switch:
- `DB=sqlite3` (default)
- `DB=postgresql` or `DB=pg`
- `DB=mysql2` or `DB=mysql`

## Architecture

- `ArelAttribute::Base` — included into ActiveRecord models, provides `define_arel_attribute` and `virtual_attribute`
- `ArelAttribute::TableProxy` — wraps `Arel::Table` to resolve virtual attributes via arel blocks
- `ArelAttribute::VirtualTotal` — aggregate virtual attributes (`virtual_total`, `virtual_sum`, etc.) using correlated subqueries
- `Arel::Nodes::ArelAttribute` — custom arel node that expands arel blocks at SQL generation time
