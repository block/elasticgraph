---
layout: query-api
title: 'ElasticGraph Query API: Pagination'
permalink: "/query-api/pagination/"
nav_title: Pagination
menu_order: 4
---
To provide pagination, ElasticGraph implements the [Relay GraphQL Cursor Connections
Specification](https://relay.dev/graphql/connections.htm). Here's an example query showing
pagination in action:

{% highlight graphql %}
{{ site.data.music_queries.pagination.PaginationExample }}
{% endhighlight %}

In addition, ElasticGraph offers some additional features beyond the Relay spec.

### Total Edge Count

As an extension to the Relay spec, ElasticGraph offers a `totalEdgeCount` field alongside `edges` and `pageInfo`.
It can be used to get a total count of matching records:

{% highlight graphql %}
{{ site.data.music_queries.pagination.Count21stCenturyArtists }}
{% endhighlight %}

Note: `totalEdgeCount` is not available under an [aggregations]({% link query-api/aggregations.md %}) field.

### Nodes

As an alternative to `edges.node`, ElasticGraph offers `nodes`. This is recommended over `edges` except when you need
a per-node `cursor` (which is available under `edges`) since it removes an extra layer of nesting, providing a simpler
response structure:

{% highlight graphql %}
{{ site.data.music_queries.pagination.PaginationNodes }}
{% endhighlight %}
