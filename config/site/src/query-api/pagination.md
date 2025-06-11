---
layout: query-api
title: 'ElasticGraph Query API: Pagination'
permalink: "/query-api/pagination/"
nav_title: Pagination
menu_order: 50
---
To provide pagination, ElasticGraph implements the [Relay GraphQL Cursor Connections
Specification](https://relay.dev/graphql/connections.htm). Here's an example query showing
pagination in action:

{% include copyable_code_snippet.html language="graphql" data="music_queries.pagination.PaginationExample" %}

This example uses `first:`, `after:`, and `pageInfo { hasNextPage, endCursor }` to implement forward pagination.
If `pageInfo.hasNextPage` indicates there is another page, the client can pass `pageInfo.endCursor` as the
`$cursor` value on the next request. Relay backwards pagination is also supported using `last:`, `before:`,
and `pageInfo { hasPreviousPage, startCursor }`.

In addition, ElasticGraph offers some additional features beyond the Relay spec.

### Total Edge Count

As an extension to the Relay spec, ElasticGraph offers a `totalEdgeCount` field alongside `edges` and `pageInfo`.
It can be used to get a total count of matching records:

{% include copyable_code_snippet.html language="graphql" data="music_queries.pagination.Count21stCenturyArtists" %}

{: .alert-note}
**Note**{: .alert-title}
`totalEdgeCount` is not available under an [aggregations]({% link query-api/aggregations.md %}) field.

### Nodes

As an alternative to `edges.node`, ElasticGraph offers `nodes`. This is recommended over `edges` except when you need
access to an edge-specific feature since it removes an extra layer of nesting, providing a simpler response structure:

{% include copyable_code_snippet.html language="graphql" data="music_queries.pagination.PaginationNodes" %}

<div class="alert-note" markdown="1">
**Note**{: .alert-title}

There are a couple of features that are available under `edges` but not `nodes`:

* **Per-node cursors**: Edges provide a `cursor` alongside each `node`.
* [**Search highlighting**]({% link query-api/highlighting.md %}): Each edge provides `highlights` and `allHighlights`.
</div>
