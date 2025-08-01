---
layout: query-api
title: 'ElasticGraph Query API: Overview'
permalink: "/query-api/overview/"
nav_title: Overview
menu_order: 10
---

ElasticGraph provides an extremely flexible GraphQL query API. As with every GraphQL API, you request the fields you want:

{% include copyable_code_snippet.html language="graphql" data="music_queries.basic.ListArtistAlbums" %}

If you're just getting started with GraphQL, we recommend you review the [graphql.org
learning materials](https://graphql.org/learn/queries/).

ElasticGraph offers a number of query features that go far beyond a traditional GraphQL
API (we like to call it "batteries included GraphQL"). Each of these features is implemented
directly by the ElasticGraph framework, ensuring consistent, predictable behavior across your
entire schema.

[Filtering]({% link query-api/filtering.md %})
: ElasticGraph's filtering support allows clients to filter on _any_ field defined in the schema
  with a wide array of filtering predicates. Native support is included to
  [negate]({% link query-api/filtering/negation.md %}) and
  [combine]({% link query-api/filtering/conjunctions.md %}) filters in arbitrary ways.

[Aggregations]({% link query-api/aggregations.md %})
: ElasticGraph includes an intuitive, flexible aggregations API which allows clients to [group
  records]({% link query-api/aggregations/grouping.md %}) by _any_ field in your schema.
  Within each grouping, clients can [count records]({% link query-api/aggregations/counts.md %})
  or compute [aggregated values]({% link query-api/aggregations/aggregated-values.md %}) over
  the set of values from any field. Further [sub-aggregations]({% link query-api/aggregations/sub-aggregations.md %})
  can be applied on list-of-object fields.

[Sorting]({% link query-api/sorting.md %})
: ElasticGraph allows clients to sort by _any_ field defined in the schema.

[Pagination]({% link query-api/pagination.md %})
: ElasticGraph implements the industry standard [Relay GraphQL Cursor Connections
  Specification](https://relay.dev/graphql/connections.htm) to support pagination, and
  extends it with support for `totalEdgeCount` and `nodes`.
  Pagination is available under both a "raw data" field (e.g `artists`) and under
  an aggregations field (e.g. `artistAggregations`).

[Highlighting]({% link query-api/highlighting.md %})
: ElasticGraph offers search highlighting, providing snippets which indicate where
  search terms matched within the returned documents.
