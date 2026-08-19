# Identify lookahead errors by response path, not by field or AST node

A resolver that builds its datastore query from a lookahead can discover that a *descendant* field is
invalid (e.g. `approximatePercentile(percentile: 150)`). It cannot raise `GraphQL::ExecutionError` for
that descendant — the raise would fail the recording field's entire subtree instead of the one bad
leaf. So the recording field records a **lookahead error** and ElasticGraph fails the flagged field
when it is resolved. This ADR records how a recorded error is matched to the field it is about.

Terms used here:

- **Recording field** — the field whose resolver holds the lookahead and observes the problem.
- **Flagged node** — the lookahead node, at any depth beneath the recording field, that the recording
  field identified as erroneous.
- **Lookahead error** — an error about a flagged node, discovered by a recording field rather than by
  the flagged node's own resolver.

**Decision**: a record is keyed by the flagged node's **absolute, index-free response path**, found by
walking down from the query's root lookahead (`context.query.lookahead`) to the flagged node's AST
nodes. At resolve time a field matches if its `context.current_path`, with list indices dropped, equals
that path.

## Considered Options

| Option | Why rejected |
|---|---|
| `[schema field, args]` | A schema field is static, so it cannot distinguish an invalid selection from a valid one of the same field elsewhere in the query. |
| AST node identity | Would require the `:ast_node` extra on every field ElasticGraph resolves — a cost paid by every query for a rare feature. |
| Recording field's exact path (indices included) + relative path | Expresses a per-list-element distinction that cannot arise (see below), at the cost of the recording field having to bind its records to a path, which datastore query memoization then has to participate in. |

## Consequences

- **The caller passes only the flagged node**, and the path is derived from `context.current_path`, so
  there is no way to misidentify the recording field. A node that isn't selected at or beneath
  `current_path` — a typo'd `Lookahead#selection` name, or a node from an unrelated part of the query —
  raises `Errors::ConfigError` at the point of misuse. That leaves nothing to detect after the fact.
- **A record may match several response positions.** A list *between* the query root and the flagged
  node collapses its indices, so one record can match every bucket of an aggregation. Each match
  produces its own error with its own path, which is what the [GraphQL
  spec](https://spec.graphql.org/October2021/#sec-Errors) requires: an execution error occurs at a
  specific response position, and its `path` is what lets clients tell an errored `null` from a real
  one. Nothing is lost, because a lookahead error is a property of the query, not of the data — a
  recording field cannot legitimately mean "bucket 1 only." `Resolvers::QueryAdapter` enforces as much
  for datastore query adapters, which must be pure functions of `(field, args, lookahead)`.
- **A record may match nothing**, legitimately, when execution never reaches the flagged position
  (e.g. the recording field resolved to an empty list). Nothing to report: unlike a raised error, an
  unreached lookahead error is simply inert.
- **A node can flag itself, not just a descendant**, since its own path matches. This lets any
  `:lookahead`-accepting resolver report its own invalid args through the same mechanism it would use
  for a descendant (by returning `QueryContext#matching_lookahead_error`) rather than raising — handy
  when the resolver wants one consistent way to fail a field.
- **Datastore query memoization needs no involvement.** Queries are memoized on
  `(field, args, lookahead)`, so on a cache hit the build — and its recording — is skipped. That's
  correct precisely because the key is index-free: a cache hit implies identical `lookahead.ast_nodes`
  (which hash by identity), hence the same document position, hence the same index-free path as the
  record made on the miss.
