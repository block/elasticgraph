---
layout: query-api
title: 'ElasticGraph Query API: Comparison Filtering'
permalink: "/query-api/filtering/comparison/"
nav_title: Comparison
menu_order: 3
---
ElasticGraph offers a standard set of comparison filter predicates:

{% include filtering_predicate_definitions/comparison.md %}

{% highlight graphql %}
{{ site.data.music_queries.filtering.FindArtistsFormedIn90s }}
{% endhighlight %}
