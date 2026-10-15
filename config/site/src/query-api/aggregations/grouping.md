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

In the example above, the grouping was performed on the raw values of the `groupedBy` fields.
However, for `Date` fields it's generally more useful to group by _truncated_ values.
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

### DateTime Grouping

`DateTime` fields offer a similar grouping API. `asDate` and `asDayOfWeek` work the same, but they accept an optional `timeZone`
argument (default is "UTC"):

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.TourAttendanceByYear" %}

Sub-day granularities (`HOUR`, `MINUTE`, `SECOND`) are supported when you use `asDateTime` instead of `asDate`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.TourAttendanceByHour" %}

Finally, you can group by the time of day (while ignoring the date) by using `asTimeOfDay`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.TourAttendanceByHourOfDay" %}

### Geographic Grouping

`GeoLocation` fields can be grouped into Web Mercator XYZ tiles using `asGeoTile`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.VenueCountsByGeoTile" %}

`zoomLevel` defaults to 7 and accepts integers from 0 through 29. At zoom level `z`, the map has
`2^z` tiles along each axis. Higher zoom levels produce smaller tiles and potentially many more
buckets. Tiles can be combined with other grouping dimensions and root aggregation results can
be paginated using the existing connection API.

Select only the representations your visualization needs:

- `zoomLevel`, `x`, and `y` identify the tile. Both coordinates range from 0 through
  `2^zoomLevel - 1`. `x` increases west to east, with `x = 0` starting at the west edge (−180°).
  `y` increases north to south, with `y = 0` starting at the north edge (approximately 85.0511°).
- `centerPoint` is the tile's center in the Web Mercator projection. It is not the average location
  of the records, nor the arithmetic midpoint of the northern and southern latitude bounds.
- `bounds` provides `north`/`south` latitudes and `east`/`west` longitudes in degrees.
- `corners` provides the same bounds as four geographic points for constructing polygons.

A missing location produces a bucket whose `asGeoTile` value is `null`. Tile objects themselves
always have all the fields listed above. Standalone geographic sub-aggregations return top buckets;
counts can be approximate, and their `countDetail.upperBound` uses the enclosing nested document count
as a conservative bound rather than claiming the counts are exact. As with other nested aggregations,
count accuracy also depends on ancestor bucket completeness.

Tiles are square on the projected map, not fixed-size areas on the ground. Ground dimensions vary
by latitude.

Tile bounds do not include the poles. Web Mercator stops at approximately ±85.0511°. The datastore
puts points north of this limit in row `y = 0`, and points south of the southern limit in the last
row (`y = 2^zoomLevel - 1`). A point can therefore be outside the bounds of the tile it is grouped into.

The datastore uses `floor` to calculate `x` and `y`, so points on shared boundaries go to the tile
to the east or south. Under this convention, a point exactly on `bounds.west` or `bounds.north`
belongs to this tile; a point on `bounds.east` or `bounds.south` belongs to the next tile.
Assignment is subject to the datastore's coordinate encoding, which can shift a boundary point;
the outermost rows and columns remain at the map's edges rather than assigning points outside the grid.

Coordinates and bounds are calculated using the standard Web Mercator inverse formulas. Small
floating-point differences from datastore calculations are possible; high-zoom bounds can also
vary by less than a centimeter due to datastore coordinate quantization.

See [OpenStreetMap's XYZ tile documentation](https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames)
for the grid convention and conversion formulas. EPSG:3857 defines the projection, not a tile-key string format.
