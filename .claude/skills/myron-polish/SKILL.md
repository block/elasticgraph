---
name: myron-polish
description: Apply Myron Marston's ElasticGraph review preferences as pre-review edits to a branch or PR. Use when polishing ElasticGraph diffs before Myron review, addressing Myron review feedback, or checking code against Myron-style review expectations.
---

# Pre-Review Polish (Myron Style)

Apply Myron Marston's review preferences to the current branch as edits. Loop until the branch is clean — no checklist violations remain and all verification passes. Distilled from his review history on merged ElasticGraph PRs.

## Usage
Invoke with: `/myron-polish [<branch>|<pr-number>]`

- No arg -> polish the current branch's diff against `origin/main` (see "Base ref" below).
- Branch or ref -> polish that branch.
- PR number -> `gh pr checkout <n>` first, then polish. Also pull the PR's unresolved review threads (step 1) so review feedback gets folded into the loop.

## Scope
This skill **edits code**. It does not write a review, produce a checklist for the author, or post to GitHub. Every issue it would otherwise comment on, it fixes in place.

Stay within the diff. Don't "tidy" unrelated files.

## Workflow

Run as a loop. Don't exit until a full iteration produces **zero edits**, **all verification commands pass**, and the final `script/quick_build` gate passes.

**Base ref:** before the first iteration, `git fetch origin main` and diff against `origin/main` — never local `main`, which may be stale and silently turn "the diff" into thousands of unrelated files. If the PR's base branch isn't `main` (`gh pr view <n> --json baseRefName`), substitute that base everywhere `origin/main` appears below.

Each iteration:

1. **Reload the change set.**
   - `git diff origin/main...HEAD`, `git status`.
   - Read every changed file end-to-end before editing — never speculate.
   - Iteration 2+: include files you edited last iteration, since your own edits can introduce new violations.
   - If polishing after review feedback, read all unresolved inline comments and confirm whether each is addressed in the current diff, stale, or still needs a code change. List them with:
     ```
     gh api graphql -f query='{ repository(owner: "block", name: "elasticgraph") { pullRequest(number: <n>) {
       reviewThreads(first: 100) { nodes { isResolved path line comments(first: 20) { nodes { author { login } body } } } } } } }' |
       jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)]'
     ```

2. **Pass 1 — Code.** Walk each non-test source file against the "Code" checklist. Apply edits.

3. **Pass 2 — Tests.** Walk each spec file against the "Tests" checklist. Apply edits.

4. **Pass 3 — Docs & artifacts.** Check READMEs, YARD annotations, RBS sigs. Apply edits. If schema definition files changed, run `bundle exec rake schema_artifacts:dump` (twice if `update_index_data.painless` changed).

5. **Pass 4 — Mechanical sweep.** Run these over `git diff origin/main...HEAD` and fix every true hit (themes
   recur in new code even after the original comment is resolved, so grep — don't rely on recall):
   - Trailing whitespace on added lines: `git diff origin/main...HEAD | grep -E '^\+.*[ \t]$'`
   - No-op churn (identical lines both removed and added): `comm -12 <(git diff origin/main...HEAD | grep '^-[^-]' | sed 's/^-//' | sort -u) <(git diff origin/main...HEAD | grep '^+[^+]' | sed 's/^+//' | sort -u)` (the `[^-]`/`[^+]` skip the `---`/`+++` file headers and blank lines) — ignore braces/`end`; cross-file moves are fine.
   - `#:` annotations missing the space: added lines matching `#:`
   - `(_ =` casts, `respond_to?`, `alias_method`, `Struct.new`, `.select {...}.map {...}` on added lines
   - `::ElasticGraph::` on added Ruby lines inside `module ElasticGraph` (justified only for real ambiguity, e.g. `SchemaDefinition` existing in two namespaces)
   - Hardcoded derived type names (`"...FilterInput"` etc.) in schema definition code

6. **Verify.** Run, in order, stopping at the first failure:
   - `script/lint --fix`
   - `script/spellcheck -w`
   - `script/type_check`
   - `script/run_gem_specs <gem>` for each gem you touched (integration/acceptance specs need the test
     datastore running: `bundle exec rake elasticsearch:test:boot`)
   Fix whatever breaks.

7. **Loop decision.**
   - If this iteration made any edits **or** any verification command failed -> record what changed, go back to step 1.
   - If this iteration made zero edits **and** every verification command passed -> leave the loop and run the final gate.

**Final gate — `script/quick_build`.** Run once, after the loop exits (it's too slow to run every iteration). It catches cross-gem fallout — e.g. a schema-definition change breaking `elasticgraph-local` acceptance specs — that per-gem runs miss. If it fails because of the diff, fix and re-enter the loop; the branch isn't clean until this passes.
- Redirect output to a log file and check the exit code directly; piping through `tail` masks the exit status.
- If failures look unrelated to the diff, re-run those specs in isolation and run `script/quick_build` on the base branch for comparison — an identical failure profile there means the failures are environmental (local datastore flakiness), not the diff. Note them in the final report instead of chasing them.

**Termination safeguard:** cap at 8 iterations. If you're still finding issues on iteration 8, stop and report what's left — that's a sign the remaining issues need author judgement.

After the final gate passes, print the final report (see "Final report" below). Do not commit. Do not push.

## Code checklist (edit when you see these)

### Naming hides implementation, exposes intent
- Method names leaking inheritance/lookup internals (`own_or_inherited_x`, `non_returnable_field_paths` when the value is formatted for `_source.excludes`) -> rename to caller-level concept (`index_def`, `source_excludes_paths`).
- Predicate methods over truthy getters. `has_own_index_def?` exists — use it in `select(&:...)` instead of `select(&:own_index_def)`.
- ES/OS domain terms used precisely. "root document type" means *root of an index* (per ES/OS docs); for "queryable off GraphQL Query" use `directly_queryable?`.

### `respond_to?` and type checks are code smells
- `respond_to?` branches that exist only because one subtype has a method the other doesn't -> push the method up to the shared mixin (usually `HasIndices`, `ImplementsInterfaces`), give the other type a trivial return (`[]`, `{}`, `nil`), delete the check.
- `is_a?`/`instance_of?` branching to pick behavior per type -> add a polymorphic method to each type instead. Adapters, schema element types, etc. are meant to be polymorphic so callers never type-check (e.g. a `cursor_type` method on each acceptance adapter, not `is_a?(CamelCaseGraphQLAcceptanceAdapter)`).

### Inheritance over parallel methods
- Two similarly shaped methods across a type + its specialization (e.g. `resolve_interface_supertypes` beside `recursively_resolve_supertypes`) -> collapse via `super`. Shared behavior in the mixin; subclass does `super + extra`.

### Arg style
- `&:method_name` shorthand over `{ |x| x.method_name }`.
- One-line recursive call as the sole in-method caller? Positional args + collapse to one line. Kwargs only when there are real external callers.
- `ElasticGraph::` and `::ElasticGraph::` prefixes inside `module ElasticGraph` -> drop in Ruby and RBS unless needed to avoid ambiguity.

### Moves and namespace changes
- File moves should be reviewable as moves. First move files with content as unchanged as possible; do indentation/module-nesting polish in a later commit or PR so GitHub can detect the move.
- Once a moved file is in its new home, use the normal nested module style:
  ```ruby
  module ElasticGraph
    module SomeGem
      # ...
    end
  end
  ```
  Then remove redundant `ElasticGraph::` prefixes made unnecessary by that nesting.
- Preserve comments unless they are inaccurate. If a move or extraction drops a comment, verify the comment is obsolete before deleting it.

### Extension mechanics
- Core gems stay ignorant of extensions. `elasticgraph-schema_definition` (and other core gems) must not reference extension concepts (warehouse columns, JSON-ingestion metadata); the extension fully implements its own logic through the extension system. A fix that adds extension-specific code to a core gem belongs in the extension instead.
- Prefer one extension strategy at a time. Use factory-applied extension modules for normal EG extension points; use `DelegateClass` wrappers when wrapping frozen/Data-backed core objects or holding side state. Do not wrap and then extend the wrapper unless the extra layer has a concrete purpose.
- Extension modules should define only new public APIs or composable overrides that call `super`. Generic private helper names can collide when multiple extensions are loaded; move those helpers into a namespaced helper class/module and delegate to it.
- If an extension module needs setup when applied, prefer an `extended` hook over requiring the caller to call a setup method immediately after `extend`.
- Reuse existing extension tables, doctest hooks, registries, and setup flows. Add the new case to the central mechanism instead of duplicating special-case setup logic.

### Collections and small churn
- Keep set-like data as `Set`. Do not switch a `Set` to an `Array` unless order or duplicates are part of the semantics, and make that reason visible in the code.
- Delete RBS or support-file churn that is not needed for `script/type_check`.
- Bug fixes found while refactoring need a targeted test, even if the refactor's broader tests already pass.
- Unused args should be removed when the caller contract allows it; do not leave compatibility-shaped parameters without a reason.
- Watch for accidental behavior drift in moves/extractions/wrappers. If behavior changes, either preserve the old behavior or add a targeted test and make the change intentional.

### Fix the root cause, not the instance
- When a bug spans a whole category (every built-in scalar, every relationship in a chain), fix it at the general level. A patch that handles only the reported case leaves its siblings broken.
- Pair the fix with a test spanning the full category — one that passes with the general fix but fails with an instance-only fix.

### Defaults & truthiness
- Explicit `true`/`false` for boolean defaults in DSL call sites. `returnable: true`, not `returnable: nil`, even if `nil` evaluates correctly.

### Impossible cases
- Guards, early-returns, and "just in case" branches for scenarios that can't happen by design -> delete, along with their tests.

### Comments and known limitations
- Non-obvious "why" gets a comment: skip/early-return cases, surprising structure, a branch that looks like it should use a value but doesn't. If a reviewer would ask "why?", answer it inline.
- Known limitations and deferred work -> link a tracking issue in the comment/TODO (`TODO(#1234): ...`, `// Known limitation--see #1234.`) so the decision has a home even when it's not fixed now.

### Config & env vars
- New ENV var reads that the AWS/SDK client already handles natively -> delete, let the SDK fall back.
- Extension config registered in `ELASTICGRAPH_CONFIG_KEYS` or added to core YAML configs -> remove.
- Avoid sidecar configuration APIs when the option belongs in the existing schema DSL. Special defaults should usually live in generated/bootstrap project configuration, not in core global default machinery.

### Gems and dependencies
- Do not add empty gem root files or matching root RBS files unless they are real public entry points or local tooling requires them.
- In gemspecs, list runtime `add_dependency` entries before `add_development_dependency` entries.
- Optional extension gems stay optional at runtime. If the test suite needs one, use `add_development_dependency` instead of making the core gem depend on it.

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
- A test the implementation could satisfy by returning a degenerate constant (`{}`, `[]`, `nil`, one hardcoded case) proves nothing. Feed non-empty / multi-case inputs so a stubbed-constant implementation fails.

### Eliminate duplicate tests
- Two tests that will always pass/fail together -> delete the less-specific one.
- Tests that duplicate behavior guaranteed by shared infra (e.g. `Support::Config` already rejects unknown keys) -> delete.

### Make tests self-contained
- Every detail that matters to a test should be visible in its body. If a helper (`team_event`, a factory) silently creates the sibling records an assertion depends on, surface that in the test. Duplication that aids understanding beats hidden setup — this coexists with "eliminate duplicate tests" (dedupe tests that add no clarity, not details that do).

### Don't couple to library internals
- Specs spying on internal `graphql` gem classes (`::GraphQL::StaticValidation::BaseVisitor`) -> replace with observable-behavior assertions (e.g. a deliberately-invalid registered query has `query.valid? == true` because validation is skipped).

### Drive behavior through the public API
- Prefer exercising behavior through the EG public API (schema definition, query execution, artifact dumping) over instantiating internal wrapper/collaborator classes directly. A test that news up internals can pass even when the piece isn't wired into the real flow (adapter registered for the wrong type, extension never applied); a public-API test fails in that case.
- Unit tests exist to exhaustively cover edge cases. Don't lean on an integration/acceptance test to incidentally cover an edge case -> add the unit test too.

### Preserve coverage when relocating tests
- Moving or rewriting a test (into another gem/file) -> port the full assertions; don't substitute a thinner version. If the original covered version-bump enforcement, metadata upkeep, etc., the replacement covers all of it.

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
- When moving a documented API, copy the useful YARD docs to the replacement API instead of leaving them on the old location or dropping them.
- RBS type comments: `# : Type` (space after `#`). Run `ag "#:"` across the diff — zero hits expected. Same for all comments.
- Prefer inline RBS type annotation comments (`value = expr # : Type`) over `_ =` casts.
- Use existing concrete RBS types when they already model the object you need; do not define local interfaces just to satisfy one extension.
- For Ruby readers that exist at runtime but Steep misses, prefer `attr_reader` plus `# @dynamic attr_name` over hand-written trivial methods or lint disables.
- Extension-module signatures stay concrete when the module is mixed into a concrete class: `module X : ::ElasticGraph::...::Y`, not custom `_Interface` shapes.
- For wrappers around frozen or `Data`-backed core objects, do not mutate or extend the core instance. Use a small delegating wrapper with an explicit delegated surface. If an extension module is intentionally mixed into that wrapper, keep any RBS interface narrow and limited to the methods the module actually calls.

### Examples and generated artifacts
- Site examples and docs fixtures should not inherit defaults that make local iteration noisier. If generated schema artifacts are ignored and should not force version bumps, set `schema.enforce_json_schema_version false` next to `schema.json_schema_version`.
- When documenting a feature, include adjacent user-facing knobs that readers will need to operate it, not only the primary happy path.
- Avoid documentation-only diff noise such as removing and re-adding identical blank lines.
- Embedded ```diff blocks inside markdown (e.g. README Rakefile examples) follow the same rules as real
  diffs: blank context lines are truly empty (never a lone space — that adds trailing whitespace and
  renders as a no-op blank-line swap), the example shows the minimal change (insert the new line; don't
  remove and re-add an adjacent blank line), and hunk headers/line numbers stay accurate to the current
  project template.

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
  script/quick_build: pass

Still needs the author's call:
  - <anything that requires a real decision, e.g. "perf claim lacks benchmark; scaffold added at benchmarks/...; please run and paste results">
  - <anything I noticed but did not change because it's out of scope for the diff>
  - <anything hit after the iteration cap>
  - <quick_build failures whose failure profile matches the base branch (environmental, not the diff)>
```

Do not commit. Do not push. Do not open or update a PR.

## Out of scope
- Writing review comments.
- Refactoring files outside the diff.
- Rewording the author's PR description or commit messages.
- `vendor/`, `Gemfile.lock`, generated schema artifacts beyond re-running the dump task.
