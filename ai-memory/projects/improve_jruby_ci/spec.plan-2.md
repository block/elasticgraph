# Plan 2: Improve JRuby CI wall clock time

## Current TODO

`## TODO: Improve JRuby CI wall clock time`

## Context

The JRuby CI build takes 50+ minutes (single job running all gems sequentially, no flatware parallelization since it requires fork). The longest non-JRuby build part takes ~20 minutes. Goal: split JRuby into parallel jobs so it's no longer the bottleneck.

## Approach

**Phase A: Measure.** Measure actual per-gem JRuby runtimes first (spec file counts aren't accurate—e.g., elasticgraph-local is particularly slow despite few files). This informs the grouping.

**Phase B: Split.** Parameterize `run_specs_for_jruby` to accept a part number. Split gems into groups balanced by measured runtime. Initial estimate (to be revised after measurement):

- **Part 1** (80 specs): `elasticgraph-graphql`
- **Part 2** (83 specs): `elasticgraph-schema_definition`, `elasticgraph-indexer`
- **Part 3** (~107 specs): all remaining gems + `elasticgraph-local`

Add JRuby CI matrix entries with `build_part_args`. Modify the `run` step to pass this extra arg. Keep `*)` default case for standalone runs.

## Files to Modify

1. `script/ci_parts/run_specs_for_jruby` - add part-based gem splitting
2. `.github/workflows/ci.yaml` - multiple JRuby matrix entries, pass `build_part_args`

## Detailed Changes

### Step 1: Measure actual JRuby per-gem runtimes

Run each gem's specs individually on JRuby and record wall clock time. Use results to balance the N-part split. Adjust gem grouping accordingly.

### Step 2: Parameterize `run_specs_for_jruby`

Rewrite `script/ci_parts/run_specs_for_jruby` (gem grouping subject to adjustment after Step 1 measurements):

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

### Step 3: Update CI yaml

In `.github/workflows/ci.yaml`:

1. Replace the single JRuby include entry with 3 entries (number may change based on Step 1):

```yaml
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

### Step 4: Verify `update_ci_yaml` handles new entries

Run `script/update_ci_yaml --verify` to confirm the script still works. The `update_includes_primary_datastore` method replaces ALL `datastore:` values in the includes section, so the new JRuby entries will be auto-updated when datastore versions change. No changes needed to `update_ci_yaml`.

## Verification

1. Run `script/update_ci_yaml --verify` to confirm CI yaml consistency.
2. Push branch and verify CI creates separate JRuby jobs with balanced runtimes.
3. Confirm each JRuby part completes in ~20 minutes or less.

## Planning Session

`/Users/myron.marston/.claude/projects/-Users-myron-marston-code-elasticgraph/f2f27953-57fc-4169-8f1d-35ce9c3e571e.jsonl`

## Unresolved Questions

(None — gem grouping will be finalized after runtime measurements in Step 1)
