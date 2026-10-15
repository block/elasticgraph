---
layout: query-api
title: 'ElasticGraph Query API: Aggregation Grouping'
permalink: "/query-api/aggregations/grouping/"
nav_title: Grouping
menu_order: 30
---
When aggregating documents, the groupings are defined by `groupedBy`. Here's an example:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.ArtistCountsByYearFormedAndHomeCountry" %}

In this case, we're grouping by multiple fields; a grouping will be returned for each
combination of `Artist.bio.yearFormed` and `Artist.bio.homeCountry` found in the data.

### Date Grouping

[Group dates]({% link query-api/aggregations/grouping/date.md %}) by calendar intervals or day of week.

### DateTime Grouping

[Group timestamps]({% link query-api/aggregations/grouping/date-time.md %}) by date, time, or day of week, with optional time zones and offsets.

### Geographic Grouping

[Group locations]({% link query-api/aggregations/grouping/geographic.md %}) into Web Mercator XYZ tiles, with selectable centers, bounds, and corners.
