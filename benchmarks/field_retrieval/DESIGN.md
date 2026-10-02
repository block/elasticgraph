# Automatic retrieval: experimental implementation

Status: implemented behind `graphql.experimental_field_retrieval: automatic`;
the default remains `source`.

ElasticGraph should choose efficient retrieval without asking schema authors to
select datastore APIs on individual fields. This replaces the `retrieved_from`
proposal in #1110 with a benchmark and an instance-level opt-in covering safe
source-free retrieval. All four retrieval APIs remain part of the investigation.

## Separate retrieval from storage

Keep returnable data in persisted `_source`. Setting `_source: false` in a search
can avoid fetching it without changing the index mapping or reindexing documents.
This preserves a fallback for queries that cannot safely use alternate retrieval.

Removing source data would be a different feature. It needs analysis of scripted
updates (which read `ctx._source`), multiple event sources, highlighting, reindexing,
and schema evolution. No storage reduction is proposed here.

## Roles for each API

| API | Proposed role |
| --- | --- |
| `_source` | Existing default, preserving original values and object/list structure. |
| `docvalue_fields` | Candidate for narrow scalar selections that can entirely avoid source retrieval. |
| `fields` | Mapping-aware retrieval; ordinary fields still read source. Consider for features requiring its semantics, not as a universal fast path. |
| `stored_fields` | Compare when already available. Do not automatically add `store: true` without a separate storage and performance analysis. |

The benchmark explicitly includes the mixed case: moving some fields to doc values
does not avoid source loading if another selected field still needs it. All-source
is the proposed default for such queries unless measurements justify more complexity.

## Eligibility before cost

The planner must first establish that alternate retrieval preserves GraphQL values.
Only then should it consider whether that path is cheaper. Begin with direct non-list
scalars and a conservative mapping allowlist. Mapping support alone is insufficient:
check GraphQL cardinality and serialization, effective mapping options, and actual
availability across index generations. Avoid dates, lossy numeric mappings, normalized
keywords, ignored values, and null substitutions until their behavior is covered.

Lists retain source retrieval: order, duplicates, null elements, and empty lists
cannot be reconstructed generally from doc values. Nested objects and fields below
object paths also retain source retrieval in the initial implementation.

Eligibility must hold across every participating index. New artifacts do not prove
that older rollover indices use the same mapping. Missing capability information
means source retrieval. A known absence of source is not a valid fallback; such a
configuration needs explicit validation rather than returning incomplete results.

## One plan, one document representation

The GraphQL instance constructs one immutable `FieldRetrieval::Source` or
`FieldRetrieval::Automatic` planner and injects it through `DatastoreQuery::Builder`.
Extensions can wrap or replace `GraphQL#field_retrieval_planner` for one instance,
or callers can inject a planner at construction. The mode string stays at the
configuration boundary instead of becoming an attribute on every query.

Root and relationship resolvers supply lookahead, and `QueryAdapter::RequestedFields`
collects datastore fields. Batching and merging may add join keys and combine selections.
`DatastoreQuery#field_retrieval_plan` lazily calls the planner when the search body is
built, memoizing one plan per immutable query. A merged query computes a new plan.
The returned `FieldRetrievalPlan` carries search parameters and decoding information.
Do not plan in leaf resolvers or in a query adapter before merging: those positions
are respectively too late or too early, and lazy field fetching risks extra requests.

Capability metadata comes from schema definitions. The offline `verify_indices.rb`
command checks current physical mappings and rollover templates before a pilot;
there is no per-query mapping discovery. It cannot certify historical values. Follow
[ROLLOUT.md](ROLLOUT.md) for the separate data-validation and canary gates.

Preserve ID-only requests using `_id`. Initially keep `request_all_fields` and
highlighting on the existing path. In experimental automatic mode, select doc values when all required payload
fields qualify, up to the default datastore request limit of 100. This is not a
measured cost threshold; wide selections of small documents may regress. Do not
enable automatic mode by default based solely on the local synthetic dataset.

Retrieved scalars are normalized once into `Document#payload`, keeping resolvers and
relationship joins independent of retrieval strategy. `SearchResponse#filter_results`
uses normalized values instead of reading raw `_source`, and retains the plan when
rebuilding or splitting batched responses. Never infer scalar/list shape
from the number of values in a datastore response.

## Evidence needed before enabling it by default

1. Run this matrix on supported Elasticsearch and OpenSearch releases, with repeated
   runs and representative documents. Find where source-free retrieval wins and
   where it regresses. Treat small differences as inconclusive.
2. The narrow eligibility planner and instance-scoped override are implemented here. Run the
   same GraphQL query through forced-source and candidate instances; compare complete
   results, relationships, pagination, abstract types, and serialization.
3. `graphql_benchmark.rb` loads a consuming project's settings, artifacts, GraphQL
   documents, and variables. Use its complete-result comparisons and strategy counts
   to validate representative application workloads. A later Rake task can wrap it.
4. Measure application latency and datastore CPU under representative concurrency.
   Account for source size, selected-field count, page size, highlighting, and the
   backend's doc-value field request limit. A safe planner falls back before exceeding it.
5. Enable a conservative automatic policy only when those results justify it.
   Application owners can validate it with the harness, but should not have to tune
   individual fields or maintain per-query benchmark winners.

References: the Elasticsearch selected-field retrieval documentation linked in
[Myron's review](https://github.com/block/elasticgraph/pull/1110#pullrequestreview-4107377831)
and the corresponding OpenSearch retrieval documentation explain the APIs. This
experiment measures their costs; it does not assume that API recommendations establish
semantic equivalence for ElasticGraph.

The rollout gates, rollback thresholds, and criteria for retiring the experimental
setting are specified in [ROLLOUT.md](ROLLOUT.md).
