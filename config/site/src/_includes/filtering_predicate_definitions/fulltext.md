[`matchesPhrase`]({% link query-api/filtering/full-text-search.md %}#matches-phrase)
: Matches records where the field value has a phrase matching the provided phrase using
  full text search. This is stricter than `matchesQuery`: all terms must match
  and be in the same order as the provided phrase.

  When `null` is passed, matches all documents.

[`matchesQuery`]({% link query-api/filtering/full-text-search.md %}#matches-query)
: Matches records where the field value matches the provided query using full text search.
  This is more lenient than `matchesPhrase`: the order of terms is ignored, and, by default,
  only one search term is required to be in the field value.

  When `null` is passed, matches all documents.

[`matchesQueryWithPrefix`]({% link query-api/filtering/full-text-search.md %}#matches-query-with-prefix)
: Matches records where the field value matches the provided query terms with prefix matching using full text search.
  Similar to `matchesQuery` but allows prefix matching on the last term in the query.

  When `null` is passed, matches all documents.
