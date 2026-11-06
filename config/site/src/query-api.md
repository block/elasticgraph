---
layout: query-api
title: Query API
permalink: /query-api/
hide_try_queries_tip: true
---

Learn how to effectively use ElasticGraph's powerful Query API to filter, aggregate, sort, paginate, and highlight your data.

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
<ul>
  {% for subpage in subpages %}
    {% assign subpage_parts = subpage.url | split: '/' %}
    {% if subpage_parts.size == 4 %}
      <li>
        <a href="{{ subpage.url | relative_url }}">{{ subpage.nav_title | default: subpage.title }}</a>
        {% assign children = subpages | where_exp: "child", "child.url contains subpage.url" | where_exp: "child", "child.url != subpage.url" %}
        {% if children.size > 0 %}
          <ul>
            {% for child in children %}
              {% assign child_parts = child.url | split: '/' %}
              {% if child_parts.size == 5 %}
                <li><a href="{{ child.url | relative_url }}">{{ child.nav_title | default: child.title }}</a></li>
              {% endif %}
            {% endfor %}
          </ul>
        {% endif %}
      </li>
    {% endif %}
  {% endfor %}
</ul>
{% endif %}

{% endfor %}
