---
layout: query-api
title: "ElasticGraph Query API: Geographic Grouping"
permalink: "/query-api/aggregations/grouping/geographic/"
nav_title: Geographic
menu_order: 30
---

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
- `centerPoint` is the point at the center of the tile on a Web Mercator map, not the average record
  location. Its latitude comes from inverse projection, not from averaging the northern and southern
  latitude bounds. For tile `1/0/0`, the projected center latitude is approximately 66.51°, while the
  average of the latitude bounds is approximately 42.53°.
- `bounds` provides `north`/`south` latitudes and `east`/`west` longitudes in degrees.
- `corners` provides `northwest`, `northeast`, `southwest`, and `southeast` geographic points for constructing polygons.

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
