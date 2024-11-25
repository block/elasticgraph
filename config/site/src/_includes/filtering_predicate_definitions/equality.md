[`equalToAnyOf`]({% link query-api/filtering/equality.md %})
: Matches records where the field value is equal to any of the provided values.
  This works just like an `IN` operator in SQL.

  When `null` is passed, matches all documents.
  When an empty list is passed, this part of the filter matches no documents.
  When `null` is passed in the list, this part of the filter matches records where the field value is `null`.
