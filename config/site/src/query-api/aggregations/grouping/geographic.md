---
layout: query-api
title: "ElasticGraph Query API: Geographic Grouping"
permalink: "/query-api/aggregations/grouping/geographic/"
nav_title: Geographic
menu_order: 30
---

`GeoLocation` fields can be grouped into [Web Mercator map tiles](https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames)
using `asGeoTile`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.aggregations.VenueCountsByGeoTile" %}

The `zoomLevel` argument (0 to 29, default 7) controls the tile size. At zoom level `z`, the map is
divided into a 2<sup>z</sup> by 2<sup>z</sup> grid, so each increase in zoom level gives tiles one quarter the size.

Each tile provides:

- `zoomLevel`, `x`, and `y`: the tile's position in the grid. `x` increases west to east and `y`
  increases north to south, both ranging from 0 up through 2<sup>z</sup> - 1.
- `mapCenterPoint`: The center of the tile as drawn on a Web Mercator map, not the average record location or the midpoint of the tile's latitude bounds. These differ noticeably only at low zoom levels: for tile 1/0/0, the map center point is at about 66.51° latitude, but the bounds midpoint is at about 42.53°.
- `bounds`: the `north` and `south` latitudes and the `east` and `west` longitudes of the tile.
- `corners`: the `northwest`, `northeast`, `southwest`, and `southeast` points of the tile, which
  are useful to draw the tile as a polygon.

Some things to keep in mind:

- Tiles are square on the map, but their size on the ground changes with latitude.
- The map stops at approximately ±85.0511° latitude. Locations nearer the poles go into the top or
  bottom row of tiles, outside of that tile's `bounds`.
- A location on the edge between two tiles goes into the tile to the east or south.
