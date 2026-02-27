# Plan 2: Improve JRuby CI wall clock time

## Current TODO

`## TODO: Improve JRuby CI wall clock time`

## Context

The JRuby CI build takes 50+ minutes (single job running all gems sequentially, no flatware parallelization since flatware requires fork). The longest non-JRuby build part takes ~20 minutes. Goal: split JRuby into parallel jobs so it's no longer the bottleneck.

Key constraints:
- Flatware unavailable on JRuby (uses fork); `script/flatware_rspec` falls back to `bundle exec rspec`
- `elasticgraph-local` must run with datastore halted (separate from other gems)
- `script/update_ci_yaml` auto-updates all `datastore:` values in the includes section; no changes needed there
- The `run` step passes args positionally: `$1`=datastore, `$2`=sleep_after_boot; we add `$3`=part

## Approach

**Phase A: Measure.** Measure actual per-gem JRuby runtimes to inform grouping. Spec file counts don't correlate well with runtime (e.g., `elasticgraph-local` is slow despite few files). Use a measurement script to time each gem individually.

**Phase B: Split.** Parameterize `run_specs_for_jruby` to accept a part number via `$3`. Split gems into groups balanced by measured runtime. Initial estimate (to be revised after measurement):

- **Part 1** (~80 specs): `elasticgraph-graphql`
- **Part 2** (~83 specs): `elasticgraph-schema_definition`, `elasticgraph-indexer`
- **Part 3** (~107 specs): all remaining gems + `elasticgraph-local` (datastore halted)

Add 3 JRuby CI matrix entries with `build_part_args`. Modify `run` step to pass `${{ matrix.build_part_args }}`. Keep `*)` default case for standalone runs.

## Files to Modify

1. `script/ci_parts/run_specs_for_jruby` — add part-based gem splitting
2. `.github/workflows/ci.yaml` — 3 JRuby matrix entries, pass `build_part_args`

## Detailed Changes

### Step 1: Measure actual JRuby per-gem runtimes

Boot datastore, then time each gem individually on JRuby. Example:

```bash
# Boot datastore first, then for each gem:
for gem in $(script/list_eg_gems.rb | grep -v elasticgraph-local); do
  if [ -d "$gem/spec" ]; then
    echo "=== $gem ==="
    time bundle exec rspec $gem/spec --format progress 2>&1 | tail -1
  fi
done
```

Use results to balance the 3-part split so each part targets ≤20 minutes.

### Step 2: Parameterize `run_specs_for_jruby`

Replace `script/ci_parts/run_specs_for_jruby` with:

```bash
#!/usr/bin/env bash

# Capture part number before `source` potentially alters positional params.
part=${3:-}

source "script/ci_parts/setup_env" "test" $1 $2

# We don't want to bother checking coverage on JRuby, for a few reasons:
# - The Ruby coverage APIs don't fully work on JRuby.
# - It slows things down.
# - We've chosen to annotate files with `# :nocov:` from an MRI perspective. Lines of code which are run on MRI but not JRuby don't have `# :nocov:`.
unset COVERAGE

# On CI, this is quite slow, and when we use the progress formatter the CI build can appear to get stuck
# because 20+ minutes may pass before the line of progress dots completes, and GitHub actions streams build
# output line-by-line. We use the documentation formatter here so that the output has many lines and there's
# more obviously ongoing progress on CI.
rspec_format="--format documentation"

run_gems_with_datastore() {
  local spec_dirs=""
  for gem in "$@"; do
    if [ -d "$gem/spec" ]; then
      spec_dirs="$spec_dirs $gem/spec"
    fi
  done
  if [ -n "$spec_dirs" ]; then
    script/flatware_rspec $spec_dirs $rspec_format
  fi
}

run_gems_with_datastore_halted() {
  halt_datastore_daemon
  for gem in $gems_to_build_with_datastore_halted; do
    bundle exec rspec $gem/spec --backtrace --format progress
  done
}

case "$part" in
  1)
    run_gems_with_datastore elasticgraph-graphql
    ;;
  2)
    run_gems_with_datastore elasticgraph-schema_definition elasticgraph-indexer
    ;;
  3)
    # All remaining gems not covered by parts 1 or 2.
    remaining=$(echo $gems_to_build_with_datastore_booted | tr ' ' '\n' | grep -v -E "^(elasticgraph-graphql|elasticgraph-schema_definition|elasticgraph-indexer)$" | tr '\n' ' ')
    run_gems_with_datastore $remaining
    run_gems_with_datastore_halted
    ;;
  *)
    # Default: run everything (backward-compatible with no part argument).
    script/run_specs $rspec_format
    run_gems_with_datastore_halted
    ;;
esac
```

Notes:
- `flatware_rspec` automatically falls back to `bundle exec rspec` on JRuby (flatware requires fork)
- Part 3 uses dynamic filtering via `grep -v` so new gems are automatically included
- `*)` default preserves standalone usage (e.g., running locally without a part number)
- Gem grouping subject to adjustment based on Step 1 measurements

### Step 3: Update CI yaml

In `.github/workflows/ci.yaml`:

1. Replace the single JRuby include entry with 3 entries:

```yaml
          # We have a special build part for JRuby, split into 3 parallel parts for speed.
          - build_part: "run_specs_for_jruby"
            ruby: "jruby-10.0"
            datastore: "elasticsearch:9.2.4"
            build_part_args: "1"
          - build_part: "run_specs_for_jruby"
            ruby: "jruby-10.0"
            datastore: "elasticsearch:9.2.4"
            build_part_args: "2"
          - build_part: "run_specs_for_jruby"
            ruby: "jruby-10.0"
            datastore: "elasticsearch:9.2.4"
            build_part_args: "3"
```

2. Update the `run` step to pass the extra arg:

```yaml
        run: script/ci_parts/${{ matrix.build_part }} ${{ matrix.datastore }} 10 ${{ matrix.build_part_args }}
```

For non-JRuby entries, `build_part_args` is undefined → empty string → shell ignores it. No impact on other build parts.

### Step 4: Verify `update_ci_yaml` handles new entries

Run `script/update_ci_yaml --verify`. The `update_includes_primary_datastore` method replaces ALL `datastore:` values in the includes section via `gsub`, so new JRuby entries get auto-updated when datastore versions change. No changes needed to `update_ci_yaml`.

## Verification

1. Run `script/update_ci_yaml --verify` — confirms CI yaml consistency.
2. Push branch and verify CI creates 3 separate JRuby jobs.
3. Confirm each JRuby part completes in ≤20 minutes.
4. Verify the `*)` default case still works for standalone local runs.

## Planning Session

`/Users/myron.marston/.claude/projects/-Users-myron-marston-code-elasticgraph/c6374ad5-86cc-4fa6-8f49-a6aad217f8a6.jsonl`

## Unresolved Questions

1. Gem grouping TBD — need Step 1 runtime measurements first. Want to do that now, or just push with the spec-file-count estimate and adjust after seeing CI times?
2. Number of parts: 3 was chosen assuming ~50 min / 3 ≈ 17 min each. If measurements show lopsided distribution, might want 4 parts instead?
