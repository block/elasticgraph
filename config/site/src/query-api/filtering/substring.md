---
layout: query-api
title: 'ElasticGraph Query API: Substring Filtering'
permalink: "/query-api/filtering/substring/"
nav_title: Substring
menu_order: 43
---

ElasticGraph offers a predicate to support substring filtering:

{% include filtering_predicate_definitions/contains.md %}

The `contains` operator accepts an object with multiple options. Here's an example using `anySubstringOf` and `ignoreCase`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.AverageSongLengthForYouOrEye" %}

This matches tracks with names that case-insensitively contain "you" or "eye" such as:

* _Brown Eyed Girl_
* _In Your Eyes_
* _We Will Rock You_
* _With or Without You_

ElasticGraph also offers `allSubstringsOf`:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.AverageSongLengthForYouAndEye" %}

This query is case-sensitive (since there's no `ignoreCase: true`) and only matches tracks with names that contain "You" and "Eye" such as _In Your Eyes_.
The following tracks only contain "You" or "Eye" (but not both) and would not be returned:

* _Brown Eyed Girl_
* _We Will Rock You_
* _With or Without You_

{: .alert-tip}
**Tip**{: .alert-title}
When searching on a single substring, `anySubstringOf` and `allSubstringsOf` behave the same, so feel free to use either.
