---
layout: query-api
title: 'ElasticGraph Query API: Filter Conjunctions'
permalink: "/query-api/filtering/conjunctions/"
nav_title: Conjunctions
menu_order: 80
---
ElasticGraph supports two conjunction predicates:

{% include filtering_predicate_definitions/conjunctions.md %}

By default, multiple filters are ANDed together. For example, this query finds artists
formed after the year 2000 with `BLUES` as one of their genres:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.FindModernBluesArtists" %}

### ORing subfilters with `anyOf`

To instead find artists who were formed after the year 2000 OR play `BLUES` music, you
can pass the sub-filters as a list-of-objects to `anyOf`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.FindModernOrBluesArtists" %}

`anyOf` is available at all levels of the filtering structure so that you can OR
sub-filters anywhere you like.

### ANDing subfilters with `allOf`

`allOf` is rarely needed since multiple filters are ANDed together by default. But it can
come in handy when you'd otherwise have a duplicate key collision on a filter input. One
case where this comes in handy is when using `anySatisfy` to [filter on a
list]({% link query-api/filtering/list.md %}). Consider this query:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.ArtistsWithPlatinum90sAlbum" %}

This query finds artists who released an album in the 90's that sold more than a million copies.
If you wanted to broaden the query to find artists with at least one 90's album and at least one
platinum-selling album--without requiring it to be the same album--you could do this:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.ArtistsWith90sAlbumAndPlatinumAlbum" %}

GraphQL input objects don't allow duplicate keys, so
`albums: {anySatisfy: {...}, anySatisfy: {...}}` isn't supported, but `allOf`
enables this use case.

<div class="alert-warning" markdown="1">
**Warning: Always Pass a List**{: .alert-title}

When using `allOf` or `anyOf`, be sure to pass the sub-filters as a list. If you instead
pass them as an object, it won't work as expected. Consider this query:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.AnyOfGotcha" %}

While this query will return results, it doesn't behave as it appears. The GraphQL
spec mandates that list inputs [coerce non-list values into a list of one
value](https://spec.graphql.org/October2021/#sec-List.Input-Coercion). In this case,
that means that the `anyOf` expression is coerced into this:

{% include copyable_code_snippet.html language="graphql" code="query AnyOfGotcha {
  artists(filter: {
    bio: {
      anyOf: [{
        yearFormed: {gt: 2000}
        description: {matchesQuery: {query: \"accordion\"}}
      }]
    }
  }) {
    # ...
  }
}" %}

Using `anyOf` with only a single sub-expression, as we have here, doesn't do anything;
the query is equivalent to:

{% include copyable_code_snippet.html language="graphql" code="query AnyOfGotcha {
  artists(filter: {
    bio: {
      yearFormed: {gt: 2000}
      description: {matchesQuery: {query: \"accordion\"}}
    }
  }) {
    # ...
  }
}" %}
</div>
