---
layout: markdown
title: 'ElasticGraph Query API: Equality Filtering'
permalink: "/query-api/filtering/equality/"
nav_title: Equality
menu_order: 2
---
The most commonly used predicate supports equality filtering:

{% include filtering_predicate_definitions/equality.md %}

Here's a basic example:

{% highlight graphql %}
{{ site.data.music_queries.filtering.EqualityFilter }}
{% endhighlight %}

Unlike the SQL `IN` operator, you can find records with `null` values if you put `null` in the list:

{% highlight graphql %}
{{ site.data.music_queries.filtering.EqualityFilterNull }}
{% endhighlight %}
