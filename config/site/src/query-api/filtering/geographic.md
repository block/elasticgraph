---
layout: query-api
title: 'ElasticGraph Query API: Geographic Filtering'
permalink: "/query-api/filtering/geographic/"
nav_title: Geographic
menu_order: 6
---
The `GeoLocation` type supports a special predicate:

{% include filtering_predicate_definitions/near.md %}

Here's an example of this predicate:

{% include copyable_code_snippet.html language="graphql" music_query="filtering.FindAsianVenues" %}
