---
layout: markdown
title: "ElasticGraph Query API: Aggregations"
permalink: /query-api/aggregations/
subpage_title: "Aggregations"
---

ElasticGraph offers a powerful aggregations API. Each indexed type gets a corresponding `*Aggregations` field.
Here's a complete example:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.BluegrassArtistAggregations }}
{% endhighlight %}

Aggregation fields support [filtering]({% link query-api/filtering.md %}) and [pagination]({% link query-api/pagination.md %})
but do _not_ support client-specified [sorting]({% link query-api/sorting.md %})[^1]. Under an aggregations field, each node
represents a grouping of documents. When [`groupedBy` fields]({% link query-api/aggregations/grouping.md %}) have been requested,
each node represents the grouping of documents that have the `groupedBy` values. When no `groupedBy` fields have been requested,
a single node will be returned containing a grouping for all documents matched by the filter.

Aggregation nodes in turn offer 4 different aggregation features.

{% include subpages.html %}

[^1]: Aggregation sorting is implicitly controlled by the [groupings]({% link query-api/aggregations/grouping.md %})--the
      nodes will sort ascending by each of the grouping fields.