---
layout: query-api
title: 'ElasticGraph Query API: Sorting'
permalink: "/query-api/sorting/"
nav_title: Sorting
menu_order: 5
---
Use `orderBy:` on a root query field to control how the results are sorted:

{% highlight graphql %}
{{ site.data.music_queries.sorting.ListArtists }}
{% endhighlight %}

This query, for example, would sort by `name` (ascending), with `bio.yearFormed` (descending) as a tie breaker.
