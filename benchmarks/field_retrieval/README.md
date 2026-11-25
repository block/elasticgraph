# Field retrieval experiment

Compare `_source`, `docvalue_fields`, `fields`, and `stored_fields` before choosing
an automatic retrieval policy for ElasticGraph. The standalone `benchmark.rb` uses
Ruby's JSON and HTTP libraries and needs no candidate library installation.
`graphql_benchmark.rb` compares complete GraphQL execution using the experimental
implementation in this PR and a consuming application's bundle.

The standalone script measures datastore searches, HTTP transport, JSON parsing,
and scalar response normalization. Its results alone do not establish a GraphQL
performance improvement or justify enabling automatic retrieval by default.

## Try the experimental GraphQL path

Source retrieval remains the default. To opt in for one application instance:

```yaml
graphql:
  experimental_field_retrieval: automatic
```

Regenerate and deploy schema artifacts with this version first:

```sh
bundle exec rake schema_artifacts:dump
```

Only runtime metadata changes; returnable fields remain in persisted `_source`.
Old artifacts without eligibility metadata fall back to source. Before enabling
the experiment on existing data, run the read-only physical-index verification:

```sh
bundle exec ruby /path/to/elasticgraph/benchmarks/field_retrieval/verify_indices.rb \
  --settings config/settings/staging.yaml > index-verification.json
```

A nonzero exit blocks the pilot. This checks current physical mappings, source
configuration, effective settings, rollover templates, and all matching generations.
It does not prove historical data cardinality or detect values ignored by older
mappings. Complete the separate data checks and workload comparisons in
[ROLLOUT.md](ROLLOUT.md) before opting in. Artifact generation does not inspect
existing indices. Eligible types are `ID`, `String`, enums, `Boolean`, `Int`,
and `JsonSafeLong`, with compatible mappings and no value-changing mapping options.
Unknown paths, lists, objects, custom scalars, dates, floating-point fields,
highlighting, requests for all fields, and more than 100 selected scalar fields use
source. Abstract selections requiring `__typename` also fall back initially.

The 100-field cap is a datastore request limit, not a measured cost threshold.
Automatic mode is an experiment: some small-document/wide-selection queries can
regress. Restore `experimental_field_retrieval: source` to roll back without
reindexing. The normal query-duration log includes `field_retrieval_counts`, with
counts for `doc_values`, `metadata_only`, `source_default`, `source_all_fields`,
`source_highlighting`, `source_field_limit`, and `source_ineligible_fields`.

## Compare complete GraphQL execution

Use an application bundle containing this PR, run from its project root, and supply
its normal settings plus a directory of representative `.graphql` queries:

```sh
bundle exec ruby /path/to/elasticgraph/benchmarks/field_retrieval/graphql_benchmark.rb \
  --settings config/settings/staging.yaml --queries benchmarks/queries \
  --warmup 20 --iterations 100 > graphql-results.json
```

Each file must contain one query operation. A companion `example.variables.json`
provides variables for `example.graphql`; otherwise variables are empty. Use stable
data, deterministic sorting, and deterministic custom resolvers. This invokes the
application's resolvers as usual, so choose suitable staging queries. The CLI uses
`QueryExecutor`'s default anonymous client and empty additional context; it does not
reproduce HTTP middleware or request authentication. Applications requiring those
must adapt the harness before comparing their workloads.

The harness creates source and automatic instances sharing the same datastore core,
warms both, randomizes run order, and compares complete GraphQL results on every run.
It measures execution through `QueryExecutor`, including resolution, joins, and
pagination; it does not include an HTTP GraphQL endpoint or final JSON encoding.
It suppresses ordinary application logging in the benchmark to avoid log I/O in the
measurements. Production strategy counts remain available on normal query logs.

The JSON report contains raw timing samples, medians, p95 values, strategy counts,
and `automatic_path_exercised`. A false value means both modes used source (or no
datastore query), so their timing difference is not evidence about doc values.
Query text, variables, settings contents, and result values are not included in the
report. Record datastore versions, hardware, and dataset details alongside it.

The standalone datastore benchmark below remains useful without installing the
candidate library; the GraphQL comparison requires the implementation in this PR.

## Synthetic dataset

Start a disposable Elasticsearch/OpenSearch node, then run:

```sh
ruby benchmarks/field_retrieval/benchmark.rb --url http://localhost:9234 > results.json
```

The script creates randomly named `eg-retrieval-bench-*` indices, populates each,
and deletes only indices it successfully created. It keeps `_source` intact.
Existing indices are not modified. A killed process may leave its generated index
behind; its name is visible in the datastore's index listing.

Defaults:

- 2,000 documents; 1 KiB and 64 KiB of additional source content per document.
- 32 scalar columns, alternating keywords and integers; select 1, 8, or 32.
- Pages of 10 and 100 hits, with stable ordering by a unique ordinal.
- 20 warmup rounds and 100 measured rounds per variant and query shape.
- One shard, no replicas, no concurrent writes, sequential requests.
- Separate pure-scalar and mixed selections. Mixed selections also return a short
  text label from source, comparing all-source retrieval with source plus doc values.

All scalar columns have `store: true` so the same index can exercise all four APIs.
This is an experimental mapping, not a recommendation to enable field storage in
ElasticGraph. Extra storage changes the index footprint; no storage savings or
indexing-throughput claims can be made from this experiment. The source padding is
seeded random hex, rather than a repeated character that compresses unrealistically.

For a quick smoke test:

```sh
ruby benchmarks/field_retrieval/benchmark.rb --url http://localhost:9234 \
  --documents 100 --padding 1024 --counts 1,8 --pages 10 \
  --warmup 2 --iterations 5 > smoke.json
```

Use `--padding`, `--counts`, and `--pages` for comma-separated matrices, and
`--documents`, `--warmup`, `--iterations`, and `--seed` to change the run size.
All synthetic dataset options are ignored in existing-index mode.

## An application's own data

Copy the script or run it from this checkout. Point it at one concrete index in a
stable staging dataset. Existing-index mode performs only mapping reads and searches:

```sh
ruby benchmarks/field_retrieval/benchmark.rb \
  --url http://localhost:9234 --index orders --fields account_id,status \
  --query search.json > results.json
```

`search.json` is a datastore search body, not a GraphQL document. Start with a search
captured from a representative ElasticGraph query. Keep only `query`, `sort`, `size`,
`from`, and `track_total_hits`; retrieval parameters are supplied by the harness.
Use deterministic sorting and fixed filter values. For example:

```json
{
  "query": {"match_all": {}},
  "sort": [{"id": "asc"}],
  "size": 100,
  "track_total_hits": false
}
```

Without a file, the script uses `match_all`, `_doc` ordering, and 100 hits. Stop writes
for the duration. The harness compares ordered IDs and values on every response;
changing data or nondeterministic ordering invalidates the comparison.

This mode accepts direct keyword/integer/boolean fields with known mapping options.
It rejects normalization, null substitution, disabled doc values, dates, floating
point, object paths, and other mappings that need a separate semantic analysis.
Source lists (even singleton lists) and objects are rejected when encountered.
The sample cannot prove the shape of every document; schema-level eligibility is
still necessary for a production planner. `stored_fields` is skipped unless all
selected fields are explicitly stored. Mixed retrieval is currently synthetic-only.

For authenticated endpoints, set `BENCH_AUTHORIZATION` through your normal secret
management mechanism. TLS certificate verification remains enabled. The report
omits the URL, index name, query body, authorization, document IDs, and field values;
field names and timing samples remain. Keep the query file locally for reproduction.

## Measurement and interpretation

The harness warms every path, randomizes variant order within each round using a
fixed seed, and reuses one HTTP connection. It disables the search request cache
and automatic HTTP retries. It does not clear filesystem/query caches: these are
warm-cache latency measurements. Do not clear shared caches to simulate cold reads.

Each response must have hits, no timeout, no failed shards, and values equal to the
other variants. Equality checking is outside the timer; payload normalization is
inside it. Null and missing scalar values both normalize to null, matching the
ordinary GraphQL field resolver. Raw response bytes and datastore `took` are recorded
alongside client wall time. `took` has millisecond resolution and excludes transport
and client work; it cannot explain tiny timing differences on its own.

JSON includes raw samples, medians, p95 values, datastore build information, Ruby
version, and run settings. Repeat runs with different seeds and capture hardware,
heap size, cluster load, and dataset characteristics when sharing results. Do not
treat one sequential local run as evidence about throughput under production load.
Use an external load generator for concurrency and a controlled environment for
cold-cache measurements. CPU usage is not measured by this script.

See [RESULTS.md](RESULTS.md) for the initial measurements and [DESIGN.md](DESIGN.md)
for how they should inform the library.

## Checking the harness

From an ElasticGraph checkout with development dependencies installed:

```sh
bundle exec rspec --options /dev/null benchmarks/field_retrieval/benchmark_spec.rb benchmarks/field_retrieval/verify_indices_spec.rb
bundle exec standardrb benchmarks/field_retrieval/*.rb
```

The specs cover scalar preservation, invalid samples, conservative mapping checks,
argument validation, mismatch detection, and existing-index read-only behavior.
The synthetic smoke test exercises real requests, all four APIs, and cleanup.

With the repository's test datastore running, also check the GraphQL harness:

```sh
bundle exec rspec -I elasticgraph-graphql/spec benchmarks/field_retrieval/graphql_benchmark_spec.rb
```

This compares complete scalar and mixed-query results through real GraphQL instances
and checks that the report distinguishes doc values from source fallback.
