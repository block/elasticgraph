---
layout: query-api
title: 'ElasticGraph Query API: Full Text Search'
permalink: "/query-api/filtering/full-text-search/"
nav_title: Full Text Search
menu_order: 50
---
ElasticGraph supports three full-text search filtering predicates:

{% include filtering_predicate_definitions/fulltext.md %}

### Matches Query

`matchesQuery` is the more lenient of the two predicates. It's designed to match broadly. Here's an example:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.AccordionOrViolinSearch" %}

This query will match artists with bios like:

> Renowned for his mesmerizing performances, Luca "The Breeze" Fontana captivates audiences with his accordion,
> weaving intricate melodies that dance between the notes of traditional folk and modern jazz.

> Sylvia  Varela's avant-garde violin playing defies tradition, blending haunting dissonance with unexpected rhythms.

Notably, the description needs `accordion` OR `violin`, but not both. In addition, it would match an artist bio that
mentioned "viola" since it supports fuzzy matching by default and "viola" is only 2 edits away from "violin". Arguments
are supported to control both aspects to make matching stricter:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.AccordionAndViolinStrictSearch" %}

### Matches Phrase

`matchesPhrase` is even stricter: it requires all terms _in the provided order_ (`matchesQuery` doesn't care about order). It's particularly useful when you want to search on a particular multi-word expression:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.PhraseSearch" %}

### Matches Query With Prefix

`matchesQueryWithPrefix` is similar to `matchesQuery` but additionally supports prefix matching on the last term of the query. This is especially useful when you want to implement search-as-you-type functionality:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.MatchesSearchWithPrefix" %}

This query will match artists with bios like:

> Marco Romano is renowned for his masterful accordion performances accompanied by violin, creating a fusion of traditional and contemporary sounds.

> The ensemble features virtuoso accordion players, producing a distinctive chamber music experience.

Notice that it matches "violin" and "virtuoso" even though the query is for "vi" (prefix match), and because `requireAllTerms: true` is specified, the bio must also contain "accordion". By setting `allowedEditsPerTerm: NONE`, we're ensuring exact matching for the terms (except for the prefix behavior on the last term).

### Bypassing matchesPhrase, matchesQuery, and matchesQueryWithPrefix

In order to make a `matchesPhrase`, `matchesQuery`, or `matchesQueryWithPrefix` filter optional, you can supply `null` to the filter input parameter, like this:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.OptionalMatchingFilter" %}
