---
layout: query-api
title: 'ElasticGraph Query API: Sub-Aggregations'
permalink: "/query-api/aggregations/sub-aggregations/"
nav_title: Sub-Aggregations
menu_order: 4
---
The example schema used throughout this guide has a number of lists-of-object fields nested
within the overall `Artist` type:

* `Artist.albums`
  * `Artist.albums[].tracks`
* `Artist.tours`
  * `Artist.tours[].shows`

ElasticGraph supports aggregations on these nested fields via `subAggregations`. This can be used
to aggregate directly on the data of one of these fields. For example, this query returns the
total sales for all albums of all artists:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.TotalAlbumSales }}
{% endhighlight %}

Sub-aggregations can also be performed under the groupings of an outer aggregation. For example,
this query returns the total album sales grouped by the home country of the artist:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.TotalAlbumSalesByArtistHomeCountry }}
{% endhighlight %}

Sub-aggregation nodes offer the standard set of aggregation operations:

* [Aggregated Values]({% link query-api/aggregations/aggregated-values.md %})
* [Counts]({% link query-api/aggregations/counts.md %})
* [Grouping]({% link query-api/aggregations/grouping.md %})
* Sub-aggregations

### Filtering Sub-Aggregations

The data included in a sub-aggregation can be filtered. For example, this query gets the total
sales of all albums released in the 21st century:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.TwentyFirstCenturyAlbumSales }}
{% endhighlight %}

### Sub-Aggregation Limitations

Sub-aggregation pagination support is limited. You can use `first` to request how many
nodes are returned, but there is no `pageInfo` and you cannot request the next page of data:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.AlbumSalesByReleaseMonth }}
{% endhighlight %}

Sub-aggregation counts are approximate. Instead of `count`, ElasticGraph offers `countDetail`
with multiple subfields:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.AlbumCount }}
{% endhighlight %}

`approximateValue`
: The (approximate) count of documents in this aggregation bucket.

  When documents in an aggregation bucket are sourced from multiple shards, the count may be only
  approximate. The `upperBound` indicates the maximum value of the true count, but usually
  the true count is much closer to this approximate value (which also provides a lower bound on the
  true count).

  When this approximation is known to be exact, the same value will be available from `exactValue`
  and `upperBound`.

`exactValue`
: The exact count of documents in this aggregation bucket, if an exact value can be determined.

  When documents in an aggregation bucket are sourced from multiple shards, it may not be possible to
  efficiently determine an exact value. When no exact value can be determined, this field will be `null`.
  The `approximateValue` field--which will never be `null`--can be used to get an approximation
  for the count.

`upperBound`
: An upper bound on how large the true count of documents in this aggregation bucket could be.

  When documents in an aggregation bucket are sourced from multiple shards, it may not be possible to
  efficiently determine an exact value. The `approximateValue` field provides an approximation,
  and this field puts an upper bound on the true count.
