---
layout: query-api
title: 'ElasticGraph Query API: Aggregated Values'
permalink: "/query-api/aggregations/aggregated-values/"
nav_title: Aggregated Values
menu_order: 10
---
Aggregated values can be computed from all values of a particular field from all documents backing an aggregation node.
Here's an example:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.BluegrassArtistLifetimeSales" %}

This example query aggregates the values of the `Artist.lifetimeSales` field using all 4 of the basic numeric
aggregated values: `min`, `max`, `avg`, and `sum`. These are qualified with `approximate` or `exact` to indicate
the level of precision they offer. The documentation for `approximateSum` and `exactSum` provides more detail:

`approximateSum`
: The (approximate) sum of the field values within this grouping.

  Sums of large `Int` values can result in overflow, where the exact sum cannot
  fit in a `JsonSafeLong` return value. This field, as a double-precision `Float`, can
  represent larger sums, but the value may only be approximate.

`exactSum`
: The exact sum of the field values within this grouping, if it fits in a `JsonSafeLong`.

  Sums of large `Int` values can result in overflow, where the exact sum cannot
  fit in a `JsonSafeLong`. In that case, `null` will be returned, and `approximateSum`
  can be used to get an approximate value.

The same example also requests two percentiles of `lifetimeSales`, using aliases (`median`/`p90`) to request
both in a single query:

`approximatePercentile`
: An approximate percentile of the field values within this grouping. The `percentile` argument specifies
  the desired percentile rank, from `0` to `100` (e.g. `50` for the median, `90` for the 90th percentile).

  Percentiles are computed using an approximate algorithm, so the returned value may not be exact--this is
  true regardless of the field's type, so there is no `exactPercentile` counterpart the way there is for
  `min`/`max`/`sum`. To request multiple percentiles in a single query, use a GraphQL alias for each
  selection, as the example above does.

Besides these basic numeric aggregated values, ElasticGraph offers one more:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.SkaArtistHomeCountries" %}

The `approximateDistinctValueCount` field uses the [HyperLogLog++ algorithm](https://research.google.com/pubs/archive/40671.pdf)
to provide an approximate count of distinct values for the field. In this case, it can give us an idea of how many countries ska
bands were formed in, in each year.
