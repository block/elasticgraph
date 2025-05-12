---
layout: query-api
title: 'ElasticGraph Query API: Filter Negation'
permalink: "/query-api/filtering/negation/"
nav_title: Negation
menu_order: 7
---
ElasticGraph supports a negation predicate:

{% include filtering_predicate_definitions/not.md %}

One of the more common use cases is to filter to non-null values:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.FindNamedVenues" %}

`not` is available at any level of a `filter`. These are equivalent:

* `name: {not: {equalToAnyOf: [null]}}`
* `not: {name: {equalToAnyOf: [null]}}`
