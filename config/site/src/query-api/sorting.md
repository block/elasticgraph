---
layout: query-api
title: 'ElasticGraph Query API: Sorting'
permalink: "/query-api/sorting/"
nav_title: Sorting
menu_order: 4
---
Use `orderBy:` on a root query field to control how the results are sorted:

{% include copyable_code_snippet.html language="graphql" data="music_queries.sorting.ListArtists" %}

This query, for example, would sort by `name` (ascending), with `bio.yearFormed` (descending) as a tie breaker.
When no `orderBy:` argument is provided, ElasticGraph will sort according to the
[default sort configured on the index]({{ '/api-docs/' | append: site.data.doc_versions.latest_version | append: '/ElasticGraph/SchemaDefinition/Indexing/Index.html#default_sort-instance_method' | relative_url }}).
