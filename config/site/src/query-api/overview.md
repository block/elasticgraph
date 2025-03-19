---
layout: query-api
title: 'ElasticGraph Query API: Overview'
permalink: "/query-api/overview/"
nav_title: Overview
menu_order: 1
---

ElasticGraph provides an extremely flexible GraphQL query API. As with every GraphQL API, you request the fields you want:

{% highlight graphql %}
{{ site.data.music_queries.basic.ListArtistAlbums }}
{% endhighlight %}

If you're just getting started with GraphQL, we recommend you review the [graphql.org learning materials](https://graphql.org/learn/queries/).

ElasticGraph offers a number of query features that go far beyond a traditional GraphQL
API. Each of these features is implemented directly by the ElasticGraph framework, ensuring
consistent, predictable behavior across your entire schema.