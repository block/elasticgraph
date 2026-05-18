---
layout: markdown
title: Namespaced Queries
permalink: /guides/namespaced-queries/
nav_title: Namespaced Queries
menu_order: 25
---

Elasticgraph allows you to create a namespace for your queries. This means that, instead of adding each root
query field to `Query`, you can declare a namespace on which your fields will be appended. By default, the root query 
fields ElasticGraph generates for an indexed type are added directly to `Query`. For example, an indexed `Widget` type 
produces `Query.widgets` and `Query.widgetAggregations`.

When ElasticGraph is composed into a federated supergraph alongside other subgraphs, `Query`
can become crowded and fields from different subgraphs can collide. A _namespace type_
lets you group ElasticGraph's root query fields under a nested path—for example, `Query.olap.widgets`
instead of `Query.widgets`. This improves discoverability and isolation of domain specific types.

## Minimal Example

A namespace is an object type declared with [`namespace_type`](/elasticgraph/api-docs/main/ElasticGraph/SchemaDefinition/API.html#namespace_type-instance_method).
You can route an indexed type's root fields to the namespace by passing `on:` to [`root_query_fields`](/elasticgraph/api-docs/main/ElasticGraph/SchemaDefinition/Mixins/HasIndices.html#root_query_fields-instance_method),
then expose the namespace type as a field on `Query`.

{% include copyable_code_snippet.html language="ruby" data="namespaced_queries.files.schema_rb" %}

The namespace type is named `OlapQuery` and is exposed
as the `olap` field on `Query`.

This produces a GraphQL API where `Widgets` are queried through `olap`:

{% include copyable_code_snippet.html language="graphql" data="namespaced_queries_queries.basic.QueryWidgets" %}

You don't need to wire up a resolver for `Query.olap`. ElasticGraph auto-resolves any no-argument
field whose return type is a namespace type.

## Nested Example

Namespace types can be nested inside other namespace types. The same auto-resolution applies, so
you don't have to configure a resolver for any intermediate field.

{% include copyable_code_snippet.html language="ruby" data="nested_namespaced_queries.files.schema_rb" %}

Widgets are now queried at `Query.olap.domain.widgets`.
