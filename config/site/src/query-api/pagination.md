---
layout: query-api
title: 'ElasticGraph Query API: Pagination'
permalink: "/query-api/pagination/"
nav_title: Pagination
menu_order: 5
---
To provide pagination, ElasticGraph implements the [Relay GraphQL Cursor Connections
Specification](https://relay.dev/graphql/connections.htm). Here's an example query showing
pagination in action:

{% highlight graphql %}
{{ site.data.music_queries.pagination.PaginationExample }}
{% endhighlight %}

This example uses `first:`, `after:`, and `pageInfo { hasNextPage, endCursor }` to implement forward pagination.
If `pageInfo.hasNextPage` indicates there is another page, the client can pass `pageInfo.endCursor` as the
`$cursor` value on the next request. Relay backwards pagination is also supported using `last:`, `before:`,
and `pageInfo { hasPreviousPage, startCursor }`.

In addition, ElasticGraph offers some additional features beyond the Relay spec.

### Total Edge Count

As an extension to the Relay spec, ElasticGraph offers a `totalEdgeCount` field alongside `edges` and `pageInfo`.
It can be used to get a total count of matching records:

{% highlight graphql %}
{{ site.data.music_queries.pagination.Count21stCenturyArtists }}
{% endhighlight %}

{: .alert-note}
**Note**{: .alert-title}
`totalEdgeCount` is not available under an [aggregations]({% link query-api/aggregations.md %}) field.

### Nodes

As an alternative to `edges.node`, ElasticGraph offers `nodes`. This is recommended over `edges` except when you need
a per-node `cursor` (which is available under `edges`) since it removes an extra layer of nesting, providing a simpler
response structure:

{% highlight graphql %}
{{ site.data.music_queries.pagination.PaginationNodes }}
{% endhighlight %}
