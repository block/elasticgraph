---
layout: markdown
title: 'ElasticGraph Query API: List Filtering'
permalink: "/query-api/filtering/list/"
nav_title: List
menu_order: 8
---
ElasticGraph supports a couple predicates for filtering on list fields:

{% include filtering_predicate_definitions/list.md %}

### Filtering on list elements with `anySatisfy`

When filtering on a list field, use `anySatisfy` to find records with matching list elements.
This query, for example, will find artists that released a platinum-selling album in the 1990s:

{% highlight graphql %}
{{ site.data.music_queries.filtering.ArtistsWithPlatinum90sAlbum }}
{% endhighlight %}

{: .alert-warning}
**Warning**{: .alert-title}
One thing to bear in mind: this query is selecting which _artists_ to return,
not which _albums_ to return. You might expect that the returned `nodes.albums` would
all be platinum-selling 90s albums, but that's not how the filtering API works. Only artists
that had a platinum-selling 90s album will be returned, and for each returned artists, all
their albums will be returned--even ones that sold poorly or were released outside the 1990s.

### Filtering on the list size with `count`

If you'd rather filter on the _size_ of a list, use `count`:

{% highlight graphql %}
{{ site.data.music_queries.filtering.FindProlificArtists }}
{% endhighlight %}
