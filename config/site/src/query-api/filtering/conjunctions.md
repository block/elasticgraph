---
layout: query-api
title: 'ElasticGraph Query API: Filter Conjunctions'
permalink: "/query-api/filtering/conjunctions/"
nav_title: Conjunctions
menu_order: 8
---
ElasticGraph supports two conjunction predicates:

{% include filtering_predicate_definitions/conjunctions.md %}

By default, multiple filters are ANDed together. For example, this query finds artists
formed after the year 2000 with "accordion" in their bio:

{% highlight graphql %}
{{ site.data.music_queries.filtering.FindRecentAccordionArtists }}
{% endhighlight %}

### ORing subfilters with `anyOf`

To instead find artists formed after the year 2000 OR with "accordion" in their bio, you
can pass the sub-filters as a list to `anyOf`:

{% highlight graphql %}
{{ site.data.music_queries.filtering.FindRecentOrAccordionArtists }}
{% endhighlight %}

`anyOf` is available at all levels of the filtering structure so that you can OR
sub-filters anywhere you like.

### ANDing subfilters with `allOf`

`allOf` is rarely needed since multiple filters are ANDed together by default. But it can
come in handy when you'd otherwise have a duplicate key collision on a filter input. One
case where this comes in handy is when using `anySatisfy` to [filter on a
list]({% link query-api/filtering/list.md %}). Consider this query:

{% highlight graphql %}
{{ site.data.music_queries.filtering.ArtistsWithPlatinum90sAlbum }}
{% endhighlight %}

This query finds artists who released an album in the 90's that sold more than million copies.
If you wanted to broaden the query to find artists with at least one 90's album and at least one
platinum-selling album--without requiring it to be the same album--you could do this:

{% highlight graphql %}
{{ site.data.music_queries.filtering.ArtistsWith90sAlbumAndPlatinumAlbum }}
{% endhighlight %}

GraphQL input objects don't allow duplicate keys, so
`albums: {anySatisfy: {...}, anySatisfy: {...}}` isn't supported, but `allOf`
enables this use case.

<div class="alert-warning" markdown="1">
**Warning: Always Pass a List**{: .alert-title}

When using `allOf` or `anyOf`, be sure to pass the sub-filters as a list. If you instead
pass them as an object, it won't work as expected. Consider this query:

{% highlight graphql %}
{{ site.data.music_queries.filtering.AnyOfGotcha }}
{% endhighlight %}

While this query will return results, it doesn't behave as it appears. The GraphQL
spec mandates that list inputs [coerce non-list values into a list of one
value](https://spec.graphql.org/October2021/#sec-List.Input-Coercion). In this case,
that means that the `anyOf` expression is coerced into this:

{% highlight graphql %}
query AnyOfGotcha {
  artists(filter: {
    bio: {
      anyOf: [{
        yearFormed: {gt: 2000}
        description: {matchesQuery: {query: "accordion"}}
      }]
    }
  }) {
    # ...
  }
}
{% endhighlight %}

Using `anyOf` with only a single sub-expression, as we have here, doesn't do anything;
the query is equivalent to:

{% highlight graphql %}
query AnyOfGotcha {
  artists(filter: {
    bio: {
      yearFormed: {gt: 2000}
      description: {matchesQuery: {query: "accordion"}}
    }
  }) {
    # ...
  }
}
{% endhighlight %}
</div>
