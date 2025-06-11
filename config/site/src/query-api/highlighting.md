---
layout: query-api
title: 'ElasticGraph Query API: Highlighting'
permalink: "/query-api/highlighting/"
nav_title: Highlighting
menu_order: 60
---

When searching through textual data it can be very useful to know where matches occurred in the returned documents.
For example, to power a "global search" box that lets users search across all string/text fields, you could use a query like this:

{% include copyable_code_snippet.html language="graphql" code=site.data.music_queries.highlighting.GlobalSearch %}

The returned `highlights` will contain snippets from the matching fields to show _why_ a particular search result was returned.

## Simpler Highlighting With `allHighlights`

ElasticGraph also offers `allHighlights` as an alternative to `highlights` which allows the query to be simplified a bit:

{% include copyable_code_snippet.html language="graphql" code=site.data.music_queries.highlighting.GlobalSearchV2 %}

Rather than providing the nested structure with named fields provided by `highlights`, this provides the highlights as a flat
list of `SearchHighlight` objects, each of which has a `path` indicating the matching field.

{: .alert-note}
**Note**{: .alert-title}
While clients usually have the option to use `edges` or `nodes`, `highlights` and `allHighlights` are only available from `edges`.
