---
layout: query-api
title: "ElasticGraph Query API: Date Grouping"
permalink: "/query-api/aggregations/grouping/date/"
nav_title: Date
menu_order: 10
---

For `Date` fields, it's generally more useful to group by _truncated_ dates than by distinct raw values.
Here's an example:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.AlbumSalesByReleaseYear" %}

In this case, we're truncating the `Album.releaseOn` dates to the year to give us one grouping per
year rather than one grouping per distinct date. The `truncationUnit` argument supports `DAY`, `MONTH`,
`QUARTER`, `WEEK` and `YEAR` values. In addition, an `offset` argument is supported, which can be used
to shift what grouping a `Date` falls into. This is particularly useful when using `WEEK`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.AlbumSalesByReleaseWeek" %}

With no offset, grouped weeks run Monday to Sunday, but we can shift it using `offset`. In this case, the weeks have been
shifted to run Sunday to Saturday.

Finally, we can also group `Date` fields by what day of week they fall into using `asDayOfWeek` instead of `asDate`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.AlbumSalesByReleaseDayOfWeek" %}
