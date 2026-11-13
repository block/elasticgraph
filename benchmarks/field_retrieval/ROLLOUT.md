# Rollout and graduation

Status: experimental, default off. The initial pilot is the repository's Widget
fixture described in [RESULTS.md](RESULTS.md). No consuming application has yet
qualified for a production canary. The following gates are proposed acceptance
criteria, not claims about completed validation.

## Before merge

Run the normal suite, type checking, and coverage checks on the final implementation.
Run the retrieval acceptance specs on the supported Elasticsearch and OpenSearch
versions in `config/tested_datastore_versions.yaml`; a snapshot build is insufficient.
The default source mode also needs regression coverage because planning, query
tracking, and response normalization are shared code.

The standalone and GraphQL benchmark specs live outside the normal gem spec paths.
CI runs them explicitly on each supported datastore through
`script/ci_parts/check_field_retrieval`. To run them locally:

```sh
bundle exec rspec --options /dev/null benchmarks/field_retrieval/benchmark_spec.rb benchmarks/field_retrieval/verify_indices_spec.rb
bundle exec rspec elasticgraph-graphql/spec/acceptance/field_retrieval_spec.rb benchmarks/field_retrieval/graphql_benchmark_spec.rb
```

## Qualify a consuming application

Before enabling the experiment in production, record one application's name, owner,
settings/artifact revision, datastore versions, and query corpus in its pilot report.
Choose an application with meaningful narrow scalar traffic and substantial source
documents, plus small documents and mixed/wide queries to measure regressions.
The application owner controls the canary and rollback; the ElasticGraph maintainer
reviews compatibility and any change to the library's default.

1. Deploy the candidate library and regenerated artifacts with retrieval still set
   to `source`. Retain persisted source and normal indexing validation.
2. Run the read-only mapping verification against each environment's settings:

   ```sh
   bundle exec ruby /path/to/elasticgraph/benchmarks/field_retrieval/verify_indices.rb \
     --settings config/settings/staging.yaml > index-verification.json
   ```

   A nonzero exit blocks the pilot. The command checks queryable indices with eligible
   payload fields, their rollover templates, and **every physical index matching the
   search expression**, including generations with obsolete suffixes. It compares
   eligible field types, doc-value availability, value-changing mapping options,
   persisted source configuration, effective coercion/ignoring settings, and the
   100-field request limit. Empty index families cannot qualify. It uses the project's
   configured clients and performs only index/template reads and index enumeration.
   Its report includes cluster/index/field names; keep it with the application's
   operational records. It does not print credentials or document values.
3. Establish historical data compatibility separately. A successful mapping check
   does not prove scalar cardinality or recover values ignored by an older mapping.
   Verify that all index generations were populated under compatible ingestion
   validation. For generations with unknown history, rebuild a staging copy from
   validated events or audit their complete data before qualifying them. Checking a
   few returned documents is insufficient. Missing doc values can otherwise look
   like a legitimate null; the runtime cannot distinguish these cases without source.
4. Run `graphql_benchmark.rb` against a stable representative staging dataset using
   the application's full query mix, variables, deterministic sorting, and resolvers.
   Compare complete results, including relationships, pagination, abstract types,
   aliases, and scalar serialization. Confirm `automatic_path_exercised` for queries
   expected to benefit. Adapt request context if the application requires it.
5. Run a load test through the application's real GraphQL endpoint, including its
   middleware and serialization. Use the expected concurrency, writes, and cache
   conditions. Repeat with at least two independent runs, and test each deployed
   supported backend version. Sequential harness timings do not establish throughput.

Proposed qualification thresholds, fixed before collecting results:

- Zero confirmed complete-result mismatches and no new query or shard errors.
- At least 10% lower median latency for the targeted scalar query class in both runs.
- No more than 5% regression in p95 or p99 latency for the overall workload or an
  important query class, including source fallback queries.
- No more than 5% higher datastore CPU at equal throughput, with no reduction in
  sustainable throughput. Record heap pressure, GC, and rejection rates as well.
- At least 10,000 executions of each important query class for tail comparisons.
  If variability prevents a conclusion, collect more evidence; do not call it a pass.

The field-count cap remains a safety limit. Qualification applies to this application's
entire workload, not just the fastest benchmark query or a field-count cutoff.

## Canary and rollback

Route 1%, 10%, 50%, then 100% of application traffic to separate GraphQL instances
configured with `experimental_field_retrieval: automatic`. Keep source-mode instances
as a contemporaneous control until qualification is complete. Each step must cover
at least 24 hours, one peak-load period, and the required sample counts before expansion.
Observe latency by query class and `field_retrieval_counts`, errors, CPU, and throughput.
Any sampled result comparison must account for concurrent writes and nondeterministic
resolvers; the benchmark assumes stable data.

Stop immediately on a confirmed result mismatch or an attributable query/shard error.
Roll back if latency or CPU crosses a qualification threshold for two consecutive
15-minute windows with sufficient samples. Restore `experimental_field_retrieval:
source` and route traffic to the source-mode instances. No mapping change or reindex
is needed. Retest after addressing the cause before resuming the canary.

Rerun compatibility verification after schema, template, physical mapping, or backend
changes, and before newly created rollover generations receive automatic traffic.
If this cannot be enforced operationally, keep the application on source retrieval.
The experiment has no automatic compatibility refresh or rollback controller.

## Long-term exit criteria

The experimental switch does not become the default solely because one pilot succeeds.
Before graduation:

1. Validate physical capabilities as part of deployment/admin operations, with cached
   information refreshed or invalidated when rollover generations change. Unknown
   compatibility selects source; avoid discovery requests on every GraphQL query.
2. Separate semantic eligibility from a simple measured cost policy. Use evidence
   across representative consuming applications, small/large documents, selection
   widths, page sizes, and all supported backends. Do not ask users to maintain
   per-field retrieval choices or per-query benchmark winners.
3. Demonstrate complete-result parity and repeatable workload-level benefit under
   concurrency, including the fallback path. Publish the tested scope and regressions.
4. Make automatic selection ordinary library behavior only after those gates pass.
   Retire the experimental setting through the normal configuration migration process;
   retain a source override for diagnosis and rollback. If the gains do not justify
   maintenance, remove the experiment and keep source retrieval.

The injected planner is the extension point for future policies. Add dates, additional
scalar mappings, `fields`, or `stored_fields` only with semantic and performance evidence.
Source removal remains a separate storage design covering scripted updates, recovery,
reindexing, highlighting, and schema evolution.
