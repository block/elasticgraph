---
layout: markdown
title: API Docs
permalink: /api-docs/
---

## Available Versions

{% for version in site.data.doc_versions.versions %}
- {% if version == 'main' %}[Development (main)]{% else %}[Version {{ version }}]{% endif %}({{ '/api-docs/' | append: version | relative_url }}){% if version == site.data.doc_versions.latest_version %} (Latest){% endif %}
{% endfor %}
