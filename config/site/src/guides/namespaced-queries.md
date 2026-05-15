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

{% include copyable_code_snippet.html language="ruby" code='ElasticGraph.define_schema do |schema|
  schema.namespace_type "OlapQuery"

  schema.on_root_query_type do |t|
    t.field "olap", "OlapQuery!"
  end

  schema.object_type "Widget" do |t|
    t.field "id", "ID"
    t.field "name", "String"
    t.index "widgets"
    t.root_query_fields plural: "widgets", on: "OlapQuery"
  end
end' %}

The namespace type is named `OlapQuery` (GraphQL types are PascalCase by convention) and is exposed
as the `olap` field on `Query` (camelCase). Throughout this guide, "namespace type" refers to the
type itself and field references like `Query.olap` refer to the field on `Query` that returns it.

This produces a GraphQL API where `Widgets` are queried through `olap`:

{% include copyable_code_snippet.html language="graphql" code="query {
  olap {
    widgets(first: 10) {
      nodes { id name }
    }
    widgetAggregations {
      nodes { count }
    }
  }
}" %}

You don't need to wire up a resolver for `Query.olap`. ElasticGraph auto-resolves any no-argument
field whose return type is a namespace type with an inert passthrough object, so each child field's
own resolver runs against it.

## Nested Example

Namespace types can be nested inside other namespace types. The same auto-resolution applies, so
you don't have to configure a resolver for any intermediate field.

{% include copyable_code_snippet.html language="ruby" code='ElasticGraph.define_schema do |schema|
  schema.namespace_type "OlapQuery" do |t|
    t.field "domain", "DomainQuery!"
  end

  schema.namespace_type "DomainQuery"

  schema.on_root_query_type do |t|
    t.field "olap", "OlapQuery!"
  end

  schema.object_type "Widget" do |t|
    t.field "id", "ID"
    t.index "widgets"
    t.root_query_fields plural: "widgets", on: "DomainQuery"
  end
end' %}

Widgets are now queried at `Query.olap.domain.widgets`.

## Tradeoffs

### Single Target per Indexed Type

An indexed type's root fields (`plural` and `singular`) are always placed together on one target
type; either `Query` (the default) or a single namespace type. You cannot split them; for example,
you cannot put `widgets` on `Query` and `widgetAggregations` on `OlapQuery`. If you need different
groupings for the list field and the aggregation field, consider whether the namespace type is
actually the right grouping, or model the split at the supergraph level.

## Apollo Federation

If you expose ElasticGraph through [elasticgraph-apollo](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Apollo.html),
namespace types appear in the `_service` SDL like any other type. Depending on your composition
strategy, you may need to apply federation directives:

- `@shareable` — if another subgraph also defines a type with the same name and overlapping fields,
  use `apollo_shareable` on the namespace type (and on shared fields) so Apollo composition allows
  the overlap.
- `@inaccessible` — use `apollo_inaccessible` on fields you don't want exposed in the final
  supergraph schema.

Namespace types you declare behave like any user-defined type — they are not tagged with
`@shareable` automatically, even if you've called `tag_built_in_types_with`. Apply the directive
explicitly when your supergraph composition requires it.
