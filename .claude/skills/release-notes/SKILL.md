# Release Notes Generator

Generate release notes for an ElasticGraph release.

## Usage
Invoke with: `/release-notes <new-version> [--from <previous-version>]`

Version numbers should NOT include the "v" prefix (the skill will add it as needed for git tags).

Examples:
- `/release-notes 1.1.0` - generates notes from latest release to HEAD
- `/release-notes 1.1.0 --from 1.0.2` - generates notes from v1.0.2 to HEAD

## Instructions

You are generating release notes for ElasticGraph. Follow this workflow:

### Step 1: Determine Version Range
1. Parse the version argument (e.g., "1.1.0") - no "v" prefix expected
2. If `--from` is provided, use that as the base version (e.g., "1.0.2")
3. Otherwise, find the most recent release tag using `gh release list --limit 1`
4. Fetch tags if needed: `git fetch --tags`
5. When referencing git tags, prepend "v" (e.g., version "1.0.2" becomes tag "v1.0.2")

### Step 2: Gather PR Information
1. Get all commits since the base version:
   ```bash
   git log v<base-version>..HEAD --oneline
   ```
2. Get all merged PRs with details:
   ```bash
   gh pr list --state merged --base main --search "merged:>=<release-date>" --limit 200 --json number,title,author,url,mergedAt
   ```
3. For key PRs, fetch full details:
   ```bash
   gh pr view <number> --json title,body
   ```

### Step 3: Comprehensive PR Discovery

**IMPORTANT**: Multiple discovery methods are needed because:
- Some PRs are squash-merged without the PR number in the commit message
- Some PRs are merged into stacked branches (not directly into main) but their changes are included via a parent PR
- The `gh pr list` date-based search may include PRs that were merged before the base tag was cut (same day, earlier timestamp)

Perform these cross-checks:
1. Extract PR numbers from `git log v<base>..HEAD --oneline` (grep for `#\d+`)
2. Get PR numbers from `gh pr list --state merged --base main --search "merged:>=<date>"` 
3. Combine both lists; any PR in the `gh` list but not in `git log` needs investigation:
   - Check `gh pr view <number> --json baseRefName` — if merged to a non-main branch, it was a stacked PR whose changes came in via a parent. Include its PR number in the parent feature's bullet.
   - Check merge timestamp vs tag timestamp — PRs merged before the tag are already in the previous release.
4. **Gap audit**: enumerate all numbers between the lowest and highest PR number in the range. For each gap, run `gh pr view` and `gh issue view` to determine if it's a closed/unmerged PR, an issue, or a merged PR we missed. Only merged-to-main PRs need coverage. Stacked PRs merged to intermediate branches should be listed with their parent feature's PR numbers.

### Step 4: Review Release Note Format
1. Read `MAINTAINERS_RUNBOOK.md` for release note structure guidelines
2. Fetch 1-2 recent release notes for format reference:
   ```bash
   gh release view <recent-version> --json body
   ```

### Step 5: Categorize PRs
Group PRs into these categories:
- **New Features**: New functionality, new gems, new APIs
- **Performance Optimizations**: Speed improvements, resource efficiency
- **Bug Fixes**: Corrections to existing behavior (single section — never split into two)
- **Other Improvements**: Documentation, tooling, refactoring, cleanup
- **Dependency Upgrades**: Grouped by type (Ruby gems, GitHub Actions, NPM, Python)

Guidelines:
- Multiple PRs implementing one feature should be combined into one bullet
- Internal-only changes (CI fixes, codebase cleanup, test fixes, typo fixes) go under "Other Improvements" as a single "Various codebase maintenance" line with all PR numbers listed
- Dependabot PRs are grouped under "Dependency Upgrades" with all PR numbers listed
- **Dependency upgrade consolidation**: ALL PRs that update, pin, exclude, or otherwise modify a dependency belong in the dependency upgrade bullet for that dependency — not in separate bug fix or other improvement sections. For example, a PR that excludes a buggy gem version, a PR that upgrades to a fixed version, and a Dependabot PR that bumps the version all belong together in one dependency line.
- There should be exactly ONE "Bug Fixes" section under "What's Changed". Do not create a separate top-level Bug Fixes section.

### Step 6: Identify New Contributors
1. Get all contributors since base version
2. Get all contributors before base version
3. New contributors = those in first list but not second
4. List them with their first PR

### Step 7: Draft Release Notes

#### Writing style for feature descriptions

- **Lead with user value, not implementation details.** For example, `returnable: false` saves storage — don't bury that under implementation details about `_source.excludes`.
- **Use ElasticGraph terminology.** Say "abstract supertypes" not "parent abstract types". Check existing docs and schema definition DSL for canonical terms.
- **Use camelCase in GraphQL examples** to match how most ElasticGraph schemas are configured. Use `query { ... }` wrappers and multi-line filter expressions for readability.
- **Be precise about scope.** If a feature only applies when using a specific gem (e.g., `elasticgraph-query_registry`), say so.
- **Distinguish "new" from "fixed".** If something was supposed to work but was broken by a later change (regression), it's a bug fix, not a new feature. For example, config validation rejecting a previously-valid value is a regression fix.
- **Don't overclaim performance wins.** Report what changed and why it matters; avoid micro-benchmark multipliers that don't reflect real-world impact (e.g., "146x faster" on a path where the overhead was never dominant). Focus on what the optimization removes or avoids.
- **For first-time support of something** (e.g., JRuby), say "for the first time" — don't version-qualify it (e.g., don't say "JRuby 10.0 support" when it's the first JRuby support ever).
- **Reference MRI as "MRI (C Ruby)"** on first mention, then just "MRI" subsequently.
- **Link to external documentation** when referencing datastore-specific features (e.g., `X-Opaque-Id` headers).

Structure:
```
ElasticGraph v<VERSION> has been released! <1-2 sentence summary>

## New Features
### <Feature Name>
Description of major features with their own subsections.

## Upgrade Notes
Any breaking changes or required migration steps.

## Performance Optimizations
### <Optimization Name>
Description of performance improvements.

## What's Changed

### New Features
* Description by @author in [#PR](url), [#PR](url)...

### Performance Optimizations
* Description by @author in [#PR](url)...

### Bug Fixes
* Description by @author in [#PR](url)...

### Other Improvements
* Description by @author in [#PR](url)...
* Various codebase maintenance by @author in [#PR](url), [#PR](url)...

### Dependency Upgrades
The datastore versions we build against have been upgraded:
* Elasticsearch: X.Y -> A.B ([#PR](url))
* OpenSearch: X.Y -> A.B ([#PR](url))

The following Ruby gems have been upgraded:
* gem-name: X.Y -> A.B ([#PR](url))
...

The following GitHub actions have been upgraded:
* Multiple actions via Dependabot ([#PR](url), ...)

The following NPM packages have been upgraded:
* package: X.Y -> A.B ([#PR](url), ...)

The following Python packages have been upgraded:
* package: X.Y -> A.B ([#PR](url), ...)

## New Contributors
* @username made their first contribution in [#PR](url)

---

**Full Changelog**: https://github.com/block/elasticgraph/compare/v<base>...v<VERSION>
```

### Step 8: Audit Coverage
1. Count total PRs since base version (exclude release PRs like "Release vX.Y.Z")
2. Count PRs mentioned in release notes
3. Identify any missing PRs and add them to appropriate sections
4. Ensure 100% coverage

### Step 9: Present for Review
Output the complete release notes and ask if any adjustments are needed.

## Notes
- The audience is ElasticGraph users — focus on user-facing changes
- Internal improvements can be grouped (e.g., "Various codebase maintenance")
- For pre-releases (rc1, rc2), use GitHub's autogenerated notes instead
- Check versioning policy if unsure whether version should be major/minor/patch
