---
layout: query-api
title: "ElasticGraph Query API: DateTime Grouping"
permalink: "/query-api/aggregations/grouping/date-time/"
nav_title: DateTime
menu_order: 20
---

Like [date grouping]({% link query-api/aggregations/grouping/date.md %}), `DateTime` fields support `asDate` and `asDayOfWeek`.
They also accept an optional `timeZone` argument (default is "UTC"):

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.TourAttendanceByYear" %}

Sub-day granularities (`HOUR`, `MINUTE`, `SECOND`) are supported when you use `asDateTime` instead of `asDate`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.TourAttendanceByHour" %}

Finally, you can group by the time of day (while ignoring the date) by using `asTimeOfDay`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.TourAttendanceByHourOfDay" %}
