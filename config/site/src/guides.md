---
layout: markdown
title: Guides
permalink: /guides/
---

Learn how to build and scale your ElasticGraph applications with our comprehensive guides.

## Available Guides

{% assign guides = site.pages | where_exp: "item", "item.path contains 'guides/'" | sort: "title" %}
{% for guide in guides %}
- [{{ guide.title | default: guide.name | remove: '.md' }}]({{ guide.url | relative_url }})
{% endfor %}

## Getting Started

Don't miss [Getting Started]({% link getting-started.md %}) to set up your first ElasticGraph project.
