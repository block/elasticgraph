---
layout: query-api
title: 'ElasticGraph Query API: Available Filter Predicates'
permalink: "/query-api/filtering/available-predicates/"
nav_title: Available Predicates
menu_order: 1
hide_try_queries_tip: true
---
ElasticGraph offers a variety of filtering predicates:

{% comment %}
  Note: these are ordered so that the predicates are sorted alphabetically. The file
  names are not alphabetical because they are named after "categories" rather than
  the predicates themselves.
{% endcomment %}

{% include filtering_predicate_definitions/conjunctions.md %}
{% include filtering_predicate_definitions/list.md %}
{% include filtering_predicate_definitions/equality.md %}
{% include filtering_predicate_definitions/comparison.md %}
{% include filtering_predicate_definitions/fulltext.md %}
{% include filtering_predicate_definitions/near.md %}
{% include filtering_predicate_definitions/not.md %}
{% include filtering_predicate_definitions/time_of_day.md %}
