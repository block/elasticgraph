---
layout: markdown
title: 'ElasticGraph Query API: Aggregation Counts'
permalink: "/query-api/aggregations/counts/"
nav_title: Counts
menu_order: 2
---
The aggregations API allows you to count documents within a grouping:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.ArtistCountsByCountry }}
{% endhighlight %}

This query, for example, returns a grouping for each country, and provides a count of how many artists
call each country home.
