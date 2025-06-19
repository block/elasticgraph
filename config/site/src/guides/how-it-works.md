---
layout: markdown
title: How ElasticGraph Works
permalink: /guides/how-it-works/
nav_title: How it Works
menu_order: 10
---

ElasticGraph is a schema-driven framework that helps you build GraphQL APIs backed by Elasticsearch or OpenSearch.
Instead of writing boilerplate code, you describe your data model using the schema definition API, and ElasticGraph
generates the artifacts needed to power your API.

Here's how it works.

### Schema Definition API

Here's an example of the schema definition API:

{% include copyable_code_snippet.html language="ruby" data="music_simplified.files.schema_rb" %}

From this schema definition, ElasticGraph generates four different schema artifacts.

### Artifact 1: `datastore_config.yaml`

The [`datastore_config.yaml` artifact]({% link guides/how-it-works/schema-artifacts/datastore_config.yaml %})
contains the full configuration of the datastore (Elasticsearch or OpenSearch) needed to support your API.
Here's a portion of what's generated from the above schema definition:

{% include copyable_code_snippet.html language="yaml" code="---
indices:
  artists:
    aliases: {}
    mappings:
      dynamic: strict
      properties:
        id:
          type: keyword
        name:
          type: keyword
        lifetimeSales:
          type: long
        albums:
          properties:
            name:
              type: keyword
            releasedOn:
              type: date
              format: strict_date
          type: nested" %}

This artifact is used by [elasticgraph-admin](https://github.com/block/elasticgraph/tree/main/elasticgraph-admin)
to administer the datastore, including both initial setup and ongoing maintenance as your schema evolves.

### Artifact 2: `json_schemas.yaml`

The [`json_schemas.yaml` artifact]({% link guides/how-it-works/schema-artifacts/json_schemas.yaml %})
defines the contract between ElasticGraph and the data publisher (that is, whichever system is responsible
for publishing data into ElasticGraph) as a [JSON schema](https://json-schema.org/). Here's a portion of what's
generated from the above schema definition:

{% include copyable_code_snippet.html language="yaml" code='---
"$schema": http://json-schema.org/draft-07/schema#
json_schema_version: 1
"$defs":
  Album:
    type: object
    properties:
      name:
        anyOf:
        - allOf:
          - "$ref": "#/$defs/String"
          - maxLength: 8191
        - type: \'null\'
      releasedOn:
        anyOf:
        - "$ref": "#/$defs/Date"
        - type: \'null\'
      __typename:
        type: string
        const: Album
        default: Album
    required:
    - name
    - releasedOn' %}

This artifact is designed to be a _public_ artifact. It should be provided to the publishing system, which can use it for:

* Code generation using a library like [json-kotlin-schema-codegen](https://github.com/pwall567/json-kotlin-schema-codegen)
* Validation in a test suite or at runtime

In addition, [elasticgraph-indexer](https://github.com/block/elasticgraph/tree/main/elasticgraph-indexer) uses a
[versioned variant of this artifact]({% link guides/how-it-works/schema-artifacts/json_schemas_by_version/v1.yaml %})
to validate all data before indexing it into the datastore.

### Artifact 3: `schema.graphql`

{% comment %}
The schema.graphql has a .txt extension to ensure it is opened in the browser as a plain text file, just
like the links to the other schema artifacts. Without using the .txt extension, we found that it was
served as `application/octet-stream` which caused it to be downloaded instead of opened in the browser.
{% endcomment %}
The [`schema.graphql` artifact]({% link guides/how-it-works/schema-artifacts/schema.graphql.txt %}) contains the
queryable schema as a GraphQL SDL file. It defines the contract between ElasticGraph and your GraphQL clients.
The schema defines the query capabilities exposed by ElasticGraph.

Some parts of the GraphQL schema are a direct translation of the types you've defined:

{% include copyable_code_snippet.html language="graphql" code="type Album {
  name: String
  releasedOn: Date
}

type Artist {
  albums: [Album!]!
  id: ID
  lifetimeSales: JsonSafeLong
  name: String
}" %}

However, most of the schema is composed of _derived_ types. For example, here's the
input ElasticGraph generates to support filtering on `Album` objects:

{% include copyable_code_snippet.html language="graphql" code="input AlbumFilterInput {
  anyOf: [AlbumFilterInput!]
  name: StringFilterInput
  not: AlbumFilterInput
  releasedOn: DateFilterInput
}" %}

This artifact is used by [elasticgraph-graphql](https://github.com/block/elasticgraph/tree/main/elasticgraph-graphql)
to provide the GraphQL endpoint. In addition, it's a public artifact which can be provided to GraphQL clients.

### Artifact 4: `runtime_metadata.yaml`

The [`runtime_metadata.yaml` artifact]({% link guides/how-it-works/schema-artifacts/runtime_metadata.yaml %}) is the
final schema artifact. It provides metaadata used by the various parts of ElasticGraph at runtime. For example,
here's some of the metadata ElasticGraph records about the `Artist` type:

{% include copyable_code_snippet.html language="yaml" code="---
object_types_by_name:
  Artist:
    graphql_fields_by_name:
      albums:
        resolver:
          name: get_record_field_value
      id:
        resolver:
          name: get_record_field_value
      lifetimeSales:
        resolver:
          name: get_record_field_value
      name:
    index_definition_names:
    - artists" %}

The runtime metadata provides all of the information needed by the various parts of ElasticGraph
to operate at runtime.
