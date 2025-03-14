---
layout: markdown
title: 'ElasticGraph Query API: Aggregated Values'
permalink: "/query-api/aggregations/aggregated-values/"
nav_title: Aggregated Values
menu_order: 1
---
Aggregated values can be computed from all values of a particular field from all documents backing an aggregation node.
Here's an example:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.BluegrassArtistLifetimeSales }}
{% endhighlight %}

This example query aggregates the values of the `Artist.lifetimeSales` field using all 4 of the standard numeric
aggregated values: `min`, `max`, `avg`, and `sum`. These are qualified with `approximate` or `exact` to indicate
the level of precision they offer. The documentation for `approximateSum` and `exactSum` provide more detail:

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

Besides these standard numeric aggregated values, ElasticGraph offers one more:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.SkaArtistHomeCountries }}
{% endhighlight %}

The `approximateDistinctValueCount` field uses the [HyperLogLog++ algorithm](https://research.google.com/pubs/archive/40671.pdf)
to provide an approximate count of distinct values for the field. In this case, it can give us an idea of how many countries ska
bands were formed in, in each year.
