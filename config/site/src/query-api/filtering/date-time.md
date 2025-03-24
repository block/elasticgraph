---
layout: query-api
title: 'ElasticGraph Query API: DateTime Filtering'
permalink: "/query-api/filtering/date-time/"
nav_title: DateTime
menu_order: 4
---
ElasticGraph supports three different date/time types:

`Date`
: A date, represented as an [ISO 8601 date string](https://en.wikipedia.org/wiki/ISO_8601).
  Example: `"2024-10-15"`.

`DateTime`
: A timestamp, represented as an [ISO 8601 time string](https://en.wikipedia.org/wiki/ISO_8601).
  Example: `"2024-10-15T07:23:15Z"`.

`LocalTime`
: A local time such as `"23:59:33"` or `"07:20:47.454"` without a time zone or offset,
  formatted based on the [partial-time portion of RFC3339](https://datatracker.ietf.org/doc/html/rfc3339#section-5.6).

All three support the standard set of [equality]({% link query-api/filtering/equality.md %}) and
[comparison]({% link query-api/filtering/comparison.md %}) predicates. When using comparison
predicates to cover a range, it's usually simplest to pair `gte` with `lt`:

{% include copyable_code_snippet.html language="graphql" music_query="filtering.FindMarch2025Shows" %}

In addition, `DateTime` fields support one more filtering operator:

{% include filtering_predicate_definitions/time_of_day.md %}

For example, you could use it to find shows that started between noon and 3 pm on any date:

{% include copyable_code_snippet.html language="graphql" music_query="filtering.FindEarlyAfternoonShows" %}
