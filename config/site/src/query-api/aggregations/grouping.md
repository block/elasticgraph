---
layout: query-api
title: 'ElasticGraph Query API: Aggregation Grouping'
permalink: "/query-api/aggregations/grouping/"
nav_title: Grouping
menu_order: 3
---
When aggregating documents, the groupings are defined by `groupedBy`. Here's an example:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.ArtistCountsByYearFormedAndHomeCountry }}
{% endhighlight %}

In this case, we're grouping by multiple fields; a grouping will be returned for each
combination of `Artist.bio.yearFormed` and `Artist.bio.homeCountry` found in the data.

### Date Grouping

In the example above, the grouping was performed on the raw values of the `groupedBy` fields.
However, for `Date` fields it's generally more useful to group by _truncated_ values.
Here's an example:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.AlbumSalesByReleaseYear }}
{% endhighlight %}

In this case, we're truncating the `Album.releaseOn` dates to the year to give us one grouping per
year rather than one grouping per distinct date. The `truncationUnit` argument supports `DAY`, `MONTH`,
`QUARTER`, `WEEK` and `YEAR` values. In addition, an `offset` argument is supported, which can be used
to shift what grouping a `Date` falls into. This is particularly useful when using `WEEK`:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.AlbumSalesByReleaseWeek }}
{% endhighlight %}

With no offset, grouped weeks run Monday to Sunday, but we can shift it using `offset`. In this case, the weeks have been
shifted to run Sunday to Saturday.

Finally, we can also group `Date` fields by what day of week they fall into using `asDayOfWeek` instead of `asDate`:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.AlbumSalesByReleaseDayOfWeek }}
{% endhighlight %}

### DateTime Grouping

`DateTime` fields offer a similar grouping API. `asDate` and `asDayOfWeek` work the same, but they accept an optional `timeZone`
argument (default is "UTC"):

{% highlight graphql %}
{{ site.data.music_queries.aggregations.TourAttendanceByYear }}
{% endhighlight %}

Sub-day granualarities (`HOUR`, `MINUTE`, `SECOND`) are supported when you use `asDateTime` instead of `asDate`:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.TourAttendanceByHour }}
{% endhighlight %}

Finally, you can group by the time of day (while ignoring the date) by using `asTimeOfDay`:

{% highlight graphql %}
{{ site.data.music_queries.aggregations.TourAttendanceByHourOfDay }}
{% endhighlight %}
