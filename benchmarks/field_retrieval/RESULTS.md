# Local results: 2026-09-10

These datastore measurements motivated the opt-in end-to-end prototype now in
this PR. The default remains source retrieval; these results do not establish a
production selection policy.

## Environment and reproduction

- Apple M3 Max, 64 GiB RAM, macOS 26.6.2; client and datastore on the same laptop.
- Ruby 3.4.9; Elasticsearch 9.0.0, bundled JDK 24, 1 GiB fixed heap.
- One shard, zero replicas, sequential HTTP requests, warmed caches, no benchmark writes during measurements.
- Default matrix: 2,000 documents, 1/64 KiB extra source content, 1/8/32 selected
  scalars, 10/100 hits, 20 warmup rounds, 100 samples per variant and case.
- Two runs with seeds 1110 and 1111. Other local application activity was not controlled.

```sh
ruby benchmarks/field_retrieval/benchmark.rb > es-1110.json
ruby benchmarks/field_retrieval/benchmark.rb --seed 1111 > es-1111.json
```

The script records raw samples and backend build information in those output files.
The tables below summarize the measured client wall time (HTTP + JSON + scalar
normalization). All compared IDs and values matched on every request.

## Source-free scalar selections

Times are milliseconds. The repeat column is source / doc values median for seed 1111.

| Extra source KiB | Fields | Hits | Source median / p95 | Doc values median / p95 | `fields` median | Stored median | Repeat source / doc values |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 10 | 1.229 / 2.315 | 1.204 / 2.156 | 1.207 | 1.111 | 0.333 / 0.299 |
| 1 | 1 | 100 | 1.164 / 1.687 | 0.909 / 1.318 | 1.274 | 0.991 | 1.045 / 0.833 |
| 1 | 8 | 10 | 0.465 / 0.676 | 0.453 / 0.762 | 0.486 | 0.458 | 0.321 / 0.314 |
| 1 | 8 | 100 | 1.743 / 2.174 | 1.662 / 1.928 | 1.898 | 1.660 | 1.346 / 1.250 |
| 1 | 32 | 10 | 1.099 / 1.742 | 1.217 / 1.765 | 1.178 | 1.119 | 0.471 / 0.540 |
| 1 | 32 | 100 | 3.296 / 3.646 | 3.318 / 3.673 | 3.546 | 3.325 | 4.034 / 4.384 |
| 64 | 1 | 10 | 1.566 / 1.853 | 1.325 / 1.663 | 1.756 | 1.329 | 1.345 / 1.155 |
| 64 | 1 | 100 | 10.738 / 11.699 | 9.053 / 10.077 | 13.168 | 9.065 | 12.610 / 9.874 |
| 64 | 8 | 10 | 1.431 / 1.633 | 1.257 / 1.489 | 1.664 | 1.252 | 1.877 / 1.789 |
| 64 | 8 | 100 | 10.782 / 11.245 | 9.149 / 9.542 | 13.226 | 9.205 | 10.624 / 8.998 |
| 64 | 32 | 10 | 1.567 / 1.816 | 1.492 / 1.754 | 1.856 | 1.434 | 1.484 / 1.410 |
| 64 | 32 | 100 | 12.472 / 26.359 | 11.017 / 23.413 | 15.116 | 11.039 | 11.968 / 10.491 |

## Mixed selections

These also select a short text label from source. The candidate reads the label from
source and the scalars from doc values. Times are median milliseconds.

| Extra source KiB | Scalars | Hits | All source | Mixed | Repeat all source | Repeat mixed |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 10 | 0.859 | 0.895 | 0.337 | 0.348 |
| 1 | 1 | 100 | 1.203 | 1.285 | 1.225 | 1.280 |
| 1 | 8 | 10 | 0.423 | 0.464 | 0.279 | 0.305 |
| 1 | 8 | 100 | 1.848 | 2.024 | 1.341 | 1.567 |
| 1 | 32 | 10 | 0.922 | 1.008 | 0.477 | 0.569 |
| 1 | 32 | 100 | 3.379 | 3.768 | 3.178 | 3.683 |
| 64 | 1 | 10 | 1.567 | 1.581 | 1.299 | 1.302 |
| 64 | 1 | 100 | 10.646 | 10.655 | 10.921 | 10.857 |
| 64 | 8 | 10 | 1.470 | 1.535 | 2.259 | 2.292 |
| 64 | 8 | 100 | 10.847 | 11.155 | 10.757 | 10.985 |
| 64 | 32 | 10 | 1.661 | 1.765 | 1.359 | 1.417 |
| 64 | 32 | 100 | 14.990 | 15.741 | 12.151 | 12.762 |

## Interpretation

For 64 KiB padding and 100 hits, source-free doc values reduced median wall time by
12–22% across the two Elasticsearch runs. Mixed retrieval ranged from about 1%
faster to 5% slower. The source-free advantage is worth investigating; the mixed
case does not justify a more complex planner on this evidence.

The 1 KiB cases have small absolute differences and some substantial between-run
variation. Do not derive a field-count cutoff or general throughput claim from them.
Stored fields were competitive, but every scalar in this fixture was explicitly
stored. That does not establish that adding storage pays for itself. `fields` did
not consistently outperform source here.

## Exploratory OpenSearch check

The same default matrix also passed on an existing local OpenSearch 3.8.0-SNAPSHOT
build (hash `1d71f7b405359d277e9d365bb0d206acce8e559b`, JDK 25, 1 GiB heap).
This is outside the supported-version matrix and is not release validation. For
64 KiB padding and 100 hits, the measured medians were:

| Scalars | Source | Doc values | All source with label | Mixed |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 10.953 | 8.186 | 10.799 | 10.823 |
| 8 | 10.992 | 8.324 | 10.969 | 11.152 |
| 32 | 12.508 | 9.784 | 12.535 | 12.749 |

The existing-index mode also passed a live OpenSearch check with three documents
containing missing/null values, false, and zero. It correctly omitted the stored-field
variant for fields without `store: true`. Synthetic indices were removed after runs.

## End-to-end GraphQL prototype

The new `graphql_benchmark.rb` was also run twice against Elasticsearch 9.0.0 on
this laptop, using a separate node with a 4 GiB fixed heap. These measurements
include GraphQL execution, datastore requests, response decoding, and GraphQL
result construction. They exclude an HTTP server and final JSON encoding.

The fixture used the repository's Widget schema and 2,000 documents in its 2019
rollover index, with routing/filter value `docvalue-benchmark-1110`. Each document
had an ID, name, integer amount, creation timestamp, a small `options` object, and
1,024 random 64-character alphanumeric tags (about 64 KiB of extra source content;
fixture seed 1110). Queries selected 100 documents sorted by ID. The scalar query
selected `id name amount_cents`; the mixed query added `options { size }`.

Both runs used 20 warmup rounds and 100 measured samples per mode, with randomized
mode order and seeds 1110 and 1111. The harness loaded the test application settings
and current schema artifacts. It compared complete GraphQL results on every execution.
The `--queries` directory contained the two queries above, with a `workspace_id`
filter and companion `.variables.json` files supplying the routing value.

```sh
bundle exec ruby benchmarks/field_retrieval/graphql_benchmark.rb \
  --settings /path/to/settings.yaml --queries /path/to/queries > graphql-1110.json
bundle exec ruby benchmarks/field_retrieval/graphql_benchmark.rb \
  --settings /path/to/settings.yaml --queries /path/to/queries --seed 1111 > graphql-1111.json
```

Times are milliseconds. Automatic mode reported `doc_values` for all 100 measured
scalar requests and `source_ineligible_fields` for all 100 mixed requests in each run.

| Query | Seed | Source median / p95 | Automatic median / p95 |
| --- | ---: | ---: | ---: |
| Scalars | 1110 | 14.322 / 15.867 | 10.935 / 12.841 |
| Scalars | 1111 | 13.511 / 15.183 | 10.378 / 12.046 |
| Mixed (source fallback) | 1110 | 16.230 / 17.552 | 16.375 / 17.935 |
| Mixed (source fallback) | 1111 | 13.675 / 16.648 | 13.524 / 16.963 |

Source-free retrieval reduced median GraphQL execution time by about 23–24% in
this particular fixture. The mixed query's roughly 1% variation is inconclusive;
both modes use source. All complete GraphQL results matched.

Next: repeat performance measurements on supported OpenSearch releases and representative consuming projects.
These local runs do not establish concurrent throughput, cold-cache behavior, CPU
savings, storage reduction, or a production selection policy.

## Compatibility validation: 2026-09-12

After injecting the instance-scoped planner and adding the physical-index preflight,
the retrieval acceptance tests and GraphQL harness checks passed against every
supported datastore version:

| Datastore | Examples | Failures |
| --- | ---: | ---: |
| Elasticsearch 9.0.0 | 14 | 0 |
| Elasticsearch 9.4.2 | 14 | 0 |
| OpenSearch 2.19.0 | 14 | 0 |
| OpenSearch 3.6.0 | 14 | 0 |

```sh
NO_VCR=1 bundle exec rspec elasticgraph-graphql/spec/acceptance/field_retrieval_spec.rb benchmarks/field_retrieval/graphql_benchmark_spec.rb
```

These checks use real datastore requests, both schema casing forms, and the actual
index/template verification code. The OpenSearch runs and Elasticsearch 9.4.2 run
also enabled `VALIDATE_GRAPHQL_SCHEMAS=1`. The local nodes used the release archives
with `mapper-size` and `analysis-icu`, matching the fixture plugins in the repository's
Dockerfiles. OpenSearch used the minimal release archives with a local compatible JDK.

The full suite passed on Elasticsearch 9.0.0: 5,143 examples, zero failures,
100% line coverage, and 100% branch coverage. Type checking, lint, spellcheck,
and schema/configuration artifact verification also passed.

This establishes compatibility for the covered cases, not a new performance result.
The September 10 latency measurements above remain historical fixture measurements;
application qualification and concurrent-load testing in [ROLLOUT.md](ROLLOUT.md)
are still required before a production canary.
