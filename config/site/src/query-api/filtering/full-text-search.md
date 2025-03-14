---
layout: markdown
title: 'ElasticGraph Query API: Full Text Search'
permalink: "/query-api/filtering/full-text-search/"
nav_title: Full Text Search
menu_order: 5
---
ElasticGraph supports two full-text search filtering predicates:

{% include filtering_predicate_definitions/fulltext.md %}

### Matches Query

`matchesQuery` is the more lenient of the two predicates. It's designed to match broadly. Here's an example:

{% highlight graphql %}
{{ site.data.music_queries.filtering.AccordionOrViolinSearch }}
{% endhighlight %}

This query will match artists with bios like:

> Renowned for his mesmerizing performances, Luca "The Breeze" Fontana captivates audiences with his accordion,
> weaving intricate melodies that dance between the notes of traditional folk and modern jazz.

> Sylvia  Varela's avant-garde violin playing defies tradition, blending haunting dissonance with unexpected rhythms.

Notably, the description needs `accordion` OR `violin`, but not both. In addition, it would match an artist bio that
mentioned "viola" since it supports fuzzy matching by default and "viola" is only 2 edits away from "violin". Arguments
are supported to control both aspects to make matching stricter:

{% highlight graphql %}
{{ site.data.music_queries.filtering.AccordionAndViolinStrictSearch }}
{% endhighlight %}

### Matches Phrase

`matchesPhrase` is even stricter: it requires all terms _in the provided order_ (`matchesQuery` doesn't care about order). It's particularly useful when you want to search on a particular multi-word expression:

{% highlight graphql %}
{{ site.data.music_queries.filtering.PhraseSearch }}
{% endhighlight %}

### Bypassing matchesPhrase and matchesQuery

In order to make a `matchesPhrase` or `matchesQuery` filter optional, you can supply `null` to the `MatchesQueryFilterInput` parameter, like this:

{% highlight graphql %}
{{ site.data.music_queries.filtering.OptionalMatchingFilter }}
{% endhighlight %}
