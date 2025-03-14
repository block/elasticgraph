---
layout: markdown
title: 'ElasticGraph Query API: Geographic Filtering'
permalink: "/query-api/filtering/geographic/"
nav_title: Geographic
menu_order: 6
---
The `GeoLocation` type supports a special predicate:

{% include filtering_predicate_definitions/near.md %}

{% highlight graphql %}
{{ site.data.music_queries.filtering.FindSeattleVenues }}
{% endhighlight %}
