---
allowed-tools: Bash(bin/rails db:*), Bash(bundle exec strong_migrations:*), Bash(grep:*), Read
argument-hint: <description of schema change>
description: Generate a safe, reversible Rails migration with zero-downtime patterns
---

## Read current state

```
!`cat db/schema.rb | grep -A5 "create_table"`
!`ls -t db/migrate | head -5`
```

Read the latest migration file for context.

## Generate migration

```
!`bin/rails generate migration $ARGUMENTS`
```

Open the generated file and fill it in following these rules:

**Zero-downtime rules (PostgreSQL):**
- Large-table index: use `algorithm: :concurrently` + `disable_ddl_transaction!` at top
- Adding NOT NULL column: add nullable → separate backfill migration → add constraint
- Renaming column: dual-write period, never single-step rename on live table
- Backfills: use `in_batches(of: 1000)` — never `Model.update_all` on full table
- Always write both `change` (or `up`/`down`) — never a one-way migration

**Enum pattern:**
```ruby
create_enum :status, ["pending", "processing", "completed", "failed"]
add_column :messages, :status, :enum, enum_type: :status, default: "pending", null: false
```

**Foreign key + index:**
```ruby
add_reference :messages, :user, foreign_key: true, index: true
```

## Apply

```
!`bin/rails db:migrate`
!`bin/rails db:schema:dump`
```

## Safety check

Never run `db:schema:load` or `db:drop` — these destroy all data. Confirm explicitly with "i confirm" if that is truly intended.
