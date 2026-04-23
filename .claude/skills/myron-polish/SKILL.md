# Pre-Review Polish (Myron Style)

Apply Myron Marston's review preferences to the current branch as edits. Loop until the branch is clean — no checklist violations remain and all verification passes. Distilled from his review history on merged ElasticGraph PRs.

## Usage
Invoke with: `/myron-polish [<branch>|<pr-number>]`

- No arg -> polish the current branch's diff against `main`.
- Branch or ref -> polish that branch.
- PR number -> `gh pr checkout <n>` first, then polish.

## Scope
This skill **edits code**. It does not write a review, produce a checklist for the author, or post to GitHub. Every issue it would otherwise comment on, it fixes in place.

Stay within the diff. Don't "tidy" unrelated files.

## Workflow

Run as a loop. Don't exit until a full iteration produces **zero edits** and **all verification commands pass**.

Each iteration:

1. **Reload the change set.**
   - `git diff main...HEAD`, `git status`.
   - Read every changed file end-to-end before editing — never speculate.
   - Iteration 2+: include files you edited last iteration, since your own edits can introduce new violations.

2. **Pass 1 — Code.** Walk each non-test source file against the "Code" checklist. Apply edits.

3. **Pass 2 — Tests.** Walk each spec file against the "Tests" checklist. Apply edits.

4. **Pass 3 — Docs & artifacts.** Check READMEs, YARD annotations, RBS sigs. Apply edits. If schema definition files changed, run `bundle exec rake schema_artifacts:dump` (twice if `update_index_data.painless` changed).

5. **Verify.** Run, in order, stopping at the first failure:
   - `script/lint --fix`
   - `script/spellcheck -w`
   - `script/type_check`
   - `script/run_gem_specs <gem>` for each gem you touched
   Fix whatever breaks.

6. **Loop decision.**
   - If this iteration made any edits **or** any verification command failed -> record what changed, go back to step 1.
   - If this iteration made zero edits **and** every verification command passed -> exit the loop.

**Termination safeguard:** cap at 8 iterations. If you're still finding issues on iteration 8, stop and report what's left — that's a sign the remaining issues need author judgement.

After exit, print the final report (see "Final report" below). Do not commit. Do not push.

## Code checklist (edit when you see these)

### Naming hides implementation, exposes intent
- Method names leaking inheritance/lookup internals (`own_or_inherited_x`, `non_returnable_field_paths` when the value is formatted for `_source.excludes`) -> rename to caller-level concept (`index_def`, `source_excludes_paths`).
- Predicate methods over truthy getters. `has_own_index_def?` exists — use it in `select(&:...)` instead of `select(&:own_index_def)`.
- ES/OS domain terms used precisely. "root document type" means *root of an index* (per ES/OS docs); for "queryable off GraphQL Query" use `directly_queryable?`.

### `respond_to?` is a code smell
- `respond_to?` branches that exist only because one subtype has a method the other doesn't -> push the method up to the shared mixin (usually `HasIndices`, `ImplementsInterfaces`), give the other type a trivial return (`[]`, `{}`, `nil`), delete the check.

### Inheritance over parallel methods
- Two similarly shaped methods across a type + its specialization (e.g. `resolve_interface_supertypes` beside `recursively_resolve_supertypes`) -> collapse via `super`. Shared behavior in the mixin; subclass does `super + extra`.

### Arg style
- `&:method_name` shorthand over `{ |x| x.method_name }`.
- One-line recursive call as the sole in-method caller? Positional args + collapse to one line. Kwargs only when there are real external callers.
- `::ElasticGraph::` prefixes inside `module ElasticGraph` -> drop.

### Defaults & truthiness
- Explicit `true`/`false` for boolean defaults in DSL call sites. `returnable: true`, not `returnable: nil`, even if `nil` evaluates correctly.

### Impossible cases
- Guards, early-returns, and "just in case" branches for scenarios that can't happen by design -> delete, along with their tests.

### Config & env vars
- New ENV var reads that the AWS/SDK client already handles natively -> delete, let the SDK fall back.
- Extension config registered in `ELASTICGRAPH_CONFIG_KEYS` or added to core YAML configs -> remove.

### Wrapper-class construction pattern
For classes like `WarehouseLambda`, `DatastoreCore`, `Indexer`, `GraphQL`, `Admin`:
- `self.from_parsed_yaml` stays small: parse config, build upstream wrappers, pass into `new`.
- `initialize(config:, dep_a:, dep_b:, clock: ::Time, s3_client: nil, ...)` — required deps as kwargs, test overrides optional.
- Locally-defined deps (classes in the same gem) are NOT ctor args. Build lazily:
  ```ruby
  def warehouse_dumper
    @warehouse_dumper ||= begin
      require "elastic_graph/warehouse_lambda/warehouse_dumper"
      WarehouseDumper.new(...)
    end
  end
  ```
- Diffs that pass locally-defined deps into `initialize` -> refactor to this pattern.

## Tests checklist

### Tests must fail when the implementation is wrong
- Before leaving a test alone, mentally revert the production change — do the tests still pass? If yes, the test is load-bearing on nothing. Strengthen the assertion or add a targeted case.
- Common gaps: clause-order swaps still pass, `name_in_index`-vs-public-name swaps still pass, parent-false/child-true traversal skipped.

### Eliminate duplicate tests
- Two tests that will always pass/fail together -> delete the less-specific one.
- Tests that duplicate behavior guaranteed by shared infra (e.g. `Support::Config` already rejects unknown keys) -> delete.

### Don't couple to library internals
- Specs spying on internal `graphql` gem classes (`::GraphQL::StaticValidation::BaseVisitor`) -> replace with observable-behavior assertions (e.g. a deliberately-invalid registered query has `query.valid? == true` because validation is skipped).

### Use the standard helpers
- Subjects via `build_*` helpers in `spec/support/builds_*.rb`. Missing helper for a new wrapper class -> add `spec/support/builds_<name>.rb` following the existing pattern.
- Logging assertions: `:capture_logs` tag + `logged_jsons_of_type(LOG_MSG_CONSTANT)`. Logger doubles -> delete.
- Wrapper classes get a single `it "returns non-nil values from each attribute" do expect_to_return_non_nil_values_from_all_attributes(build_xyz) end`.

### Cover the right axes
When the diff adds a schema feature, ensure specs cover:
- leaf and object fields
- nested paths (`grandparent.parent.child`)
- `graphql_only: true` and `indexing_only: true` variants
- `name_in_index:` explicitly configured
- predicates where parent and child disagree, in both directions
- at least one `config/schema/widgets.rb` field using the feature, plus an acceptance test exercising filter/sort/group/aggregate/highlight as relevant

### Test description consistency
- Adjacent `it "..."` descriptions in the same group should use consistent phrasing. `it "includes X in _source.excludes"` next to `it "excludes X ..."` reads as opposite results — standardize to one form.

## Docs & artifacts checklist

### READMEs track user-visible behavior
- Diff changes runtime behavior users depend on (e.g. skipping validation) -> gem README calls it out with the new expectation (e.g. "runtime validation is skipped; CI must run the validation rake task").
- Include concrete benchmark numbers when they motivate the feature.
- Gem READMEs duplicating `CONTRIBUTING.md` (per-gem "Local Development" sections) -> remove.
- Code-y tokens wrapped in backticks. Render-check tables, SDL, rake tasks, S3 key templates.

### YARD + RBS
- New public attrs get `@!attribute`. New kwargs get `@param`.
- RBS type comments: `# : Type` (space after `#`). Run `ag "#:"` across the diff — zero hits expected. Same for all comments.
- Extension-module signatures stay concrete: `module X : ::ElasticGraph::...::Y`, not custom `_Interface` shapes.

### Imports and requires
- Top-of-file `require`s alphabetical.

### Schema artifacts
- `config/schema/` or `elasticgraph-schema_definition/` changed -> `bundle exec rake schema_artifacts:dump`. Twice if `update_index_data.painless` changed.

## Perf

- Perf-win claims require a `benchmark-ips` script under `benchmarks/<area>/<name>.rb` with `<name>.results.txt` capturing before/after. Missing -> add the script scaffold; flag for the author to run.
- `require`s inside memoized methods, not at the top, when the class using them is only reached via a specific builder.

## Final report

When the loop exits, print:

```
Polished: <branch>  (iterations: <n>)

Fixes applied:
  Code:
    - <file>: <short description>
    ...
  Tests:
    - <file>: <short description>
    ...
  Docs/artifacts:
    - <file>: <short description>
    ...

Verification (final iteration):
  script/lint --fix: pass
  script/spellcheck -w: pass
  script/type_check: pass
  script/run_gem_specs <gem>: pass
  ...

Still needs the author's call:
  - <anything that requires a real decision, e.g. "perf claim lacks benchmark; scaffold added at benchmarks/...; please run and paste results">
  - <anything I noticed but did not change because it's out of scope for the diff>
  - <anything hit after the iteration cap>
```

Do not commit. Do not push. Do not open or update a PR.

## Out of scope
- Writing review comments.
- Refactoring files outside the diff.
- Rewording the author's PR description or commit messages.
- `vendor/`, `Gemfile.lock`, generated schema artifacts beyond re-running the dump task.
