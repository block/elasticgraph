---
layout: query-api
title: 'ElasticGraph Query API: Equality Filtering'
permalink: "/query-api/filtering/equality/"
nav_title: Equality
menu_order: 2
---
The most commonly used predicate supports equality filtering:

{% include filtering_predicate_definitions/equality.md %}

Here's a basic example:

{% include copyable_code_snippet.html language="graphql" music_query="filtering.FindU2OrRadiohead" %}

Unlike the SQL `IN` operator, you can find records with `null` values if you put `null` in the list:

{% include copyable_code_snippet.html language="graphql" music_query="filtering.FindUnnamedVenues" %}
