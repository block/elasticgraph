---
layout: query-api
title: Query API
permalink: /query-api/
hide_try_queries_tip: true
---

Learn how to effectively use ElasticGraph's powerful Query API to search, filter, sort, and aggregate your data.

## Documentation Sections

{% comment %}Get top-level section pages{% endcomment %}
{% assign sections = "" | split: "" %}
{% for page in site.pages %}
  {% assign path_parts = page.url | split: "/" %}
  {% if path_parts.size == 3 and page.url contains "/query-api/" and page.url != "/query-api/" %}
    {% assign sections = sections | push: page %}
  {% endif %}
{% endfor %}
{% assign sections = sections | sort: "menu_order" %}

{% for section in sections %}
### [{{ section.nav_title | default: section.title }}]({{ section.url | relative_url }})
{% if section.description %}
{{ section.description }}
{% endif %}

{% assign subpages = site.pages | where_exp: "page", "page.url contains section.url" | where_exp: "page", "page.url != section.url" | sort: "menu_order" %}
{% if subpages.size > 0 %}
{% for subpage in subpages %}
- [{{ subpage.nav_title | default: subpage.title }}]({{ subpage.url | relative_url }})
{% endfor %}
{% endif %}

{% endfor %}
