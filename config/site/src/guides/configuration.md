---
layout: markdown
title: Configuration Settings
permalink: /guides/configuration/
nav_title: Configuration
menu_order: 15
---

ElasticGraph provides a comprehensive configuration system that allows you to customize every aspect of your application's behavior.

### Downloads

Different ElasticGraph versions have had slightly different configuration schemas. We provide downloads for multiple versions here.

{% for version in site.data.config_artifacts.ordered_versions %}
  {% if version == "main" %}
#### Latest Development Version (main)
  {% else %}
#### Version {{ version }}
  {% endif %}

  {% assign base_path = "/guides/configuration/" | append: version | append: "/" %}
  {% assign example_yaml = base_path | append: "elasticgraph-config-example.yaml" | relative_url %}
  {% assign schema_yaml = base_path | append: "elasticgraph-config-schema.yaml" | relative_url %}
  {% assign schema_json = base_path | append: "elasticgraph-config-schema.json" | relative_url %}

- <a href="{{ example_yaml }}" download="{{ example_yaml }}"><strong>Example Configuration</strong></a>: Complete example configuration file with inline comments.
- **Configuration Schema**: JSON schema for validation and local IDE support, available as <a href="{{ schema_yaml }}" download="{{ schema_yaml }}">YAML</a> or <a href="{{ schema_json }}" download="{{ schema_json }}">JSON</a>.

{% endfor %}

This rest of this guide covers the available configuration options in the latest ElasticGraph release ({{ site.data.doc_versions.latest_version }}).

### Configuration File Structure

Configuration settings files conventionally go in `config/settings`:

{% include copyable_code_snippet.html language="text" code="config
└── settings
    ├── local.yaml
    ├── production.yaml
    └── staging.yaml" %}

Different configuration settings files can then be used in different environments.

### Example Configuration

{% assign latest_example_yaml = "/guides/configuration/" | append: site.data.doc_versions.latest_version | append: "/elasticgraph-config-example.yaml" | relative_url %}

Here's a complete example configuration settings file with inline comments explaining each section. Alternately, you can
<a href="{{ latest_example_yaml }}" download="{{ latest_example_yaml }}">download this example</a>.

{% include copyable_code_snippet.html language="yaml" data="config_artifacts.files.elasticgraph-config-example_yaml" %}

### Configuration Schema

{% assign latest_schema_yaml = "/guides/configuration/" | append: site.data.doc_versions.latest_version | append: "/elasticgraph-config-schema.yaml" | relative_url %}
{% assign latest_schema_json = "/guides/configuration/" | append: site.data.doc_versions.latest_version | append: "/elasticgraph-config-schema.json" | relative_url %}

ElasticGraph validates configuration settings using the JSON schema shown below. It can also be downloaded as
<a href="{{ latest_schema_yaml }}" download="{{ latest_schema_yaml }}">YAML</a> or
<a href="{{ latest_schema_json }}" download="{{ latest_schema_json }}">JSON</a> for local
usage (e.g. in an IDE).

{% include copyable_code_snippet.html language="yaml" data="config_artifacts.files.elasticgraph-config-schema_yaml" %}
