[`matchesPhrase`]({% link query-api/filtering/full-text-search.md %})
: Matches records where the field value has a phrase matching the provided phrase using
  full text search. This is stricter than `matchesQuery`: all terms must match
  and be in the same order as the provided phrase.

  Will be ignored when `null` is passed.

[`matchesQuery`]({% link query-api/filtering/full-text-search.md %})
: Matches records where the field value matches the provided query using full text search.
  This is more lenient than `matchesPhrase`: the order of terms is ignored, and, by default,
  only one search term is required to be in the field value.

  Will be ignored when `null` is passed.
