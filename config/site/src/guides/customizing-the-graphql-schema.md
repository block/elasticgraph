---
layout: markdown
title: Customizing the GraphQL Schema
permalink: /guides/customizing-the-graphql-schema/
nav_title: Customizing the Schema
menu_order: 25
---

ElasticGraph generates a complete GraphQL API from your schema definition, including filter inputs, aggregations,
sort orders, connections, and more. This guide covers the customization options available to you to shape the generated
schema to fit your project's conventions.

The customizations fall into two groups:

- **Naming options** are passed to [`Local::RakeTasks`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html)
  in your `Rakefile`. They control the casing and spelling of generated names without changing schema structure.
- **Schema definition hooks** are called inside `ElasticGraph.define_schema` and let you mutate generated types and
  fields—adding directives, documentation, or grouping fields under namespace types.

## Casing of Generated Fields

Set [`schema_element_name_form`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#schema_element_name_form-instance_method)
to choose between `:camelCase` (the default) and `:snake_case` for every generated field name, argument name, and
directive name in the SDL. Generated types like `WidgetFilterInput` are unaffected; only the elements within them.

{% include copyable_code_snippet.html language="ruby" code='ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/local.yaml",
  path_to_schema: "config/schema.rb"
) do |tasks|
  tasks.schema_element_name_form = :snake_case
end' %}

## Renaming Generated Fields, Arguments, and Directives

Use [`schema_element_name_overrides`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#schema_element_name_overrides-instance_method)
to rename individual generated fields, arguments, or directives. For example, to spell out filter operators that 
ElasticGraph abbreviates by default:

{% include copyable_code_snippet.html language="ruby" code='ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/local.yaml",
  path_to_schema: "config/schema.rb"
) do |tasks|
  tasks.schema_element_name_overrides = {
    gt: "greaterThan",
    gte: "greaterThanOrEqualTo",
    lt: "lessThan",
    lte: "lessThanOrEqualTo"
  }
end' %}

To rename specific values within a generated enum (e.g. `DayOfWeek.MONDAY` to `DayOfWeek.MON`), use
[`enum_value_overrides_by_type`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#enum_value_overrides_by_type-instance_method).

## Naming Formats for Derived Types

For each indexed type, ElasticGraph generates a family of derived types with names like `WidgetFilterInput`,
`WidgetAggregation`, and `WidgetSortOrder`. The suffix patterns are configured by
[`derived_type_name_formats`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#derived_type_name_formats-instance_method).

For example, to shorten `WidgetFilterInput` to `WidgetFilter` across the entire schema:

{% include copyable_code_snippet.html language="ruby" code='ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/local.yaml",
  path_to_schema: "config/schema.rb"
) do |tasks|
  tasks.derived_type_name_formats = {FilterInput: "%{base}Filter"}
end' %}

The full set of customizable formats is documented at
[`SchemaElements::TypeNamer::DEFAULT_FORMATS`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/TypeNamer.html#DEFAULT_FORMATS-constant).
The `%{base}` placeholder is replaced with the indexed type's name; format strings must preserve every placeholder
the default uses, or schema generation fails with a config error.

## Renaming Individual Types

When you need to rename a single type rather than a whole family—for example, swapping ElasticGraph's `JsonSafeLong`
scalar for one with a name your team prefers—use
[`type_name_overrides`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#type_name_overrides-instance_method):

{% include copyable_code_snippet.html language="ruby" code='ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/local.yaml",
  path_to_schema: "config/schema.rb"
) do |tasks|
  tasks.type_name_overrides = {JsonSafeLong: "BigInt"}
end' %}

The standard GraphQL scalars (`Boolean`, `Float`, `ID`, `Int`, `String`) and the root `Query` type cannot be renamed
this way.

## Customization Hooks

The schema definition DSL exposes hooks that let you mutate generated types and fields; typically to add
directives like `@deprecated` or to append documentation. Hooks are called inside `ElasticGraph.define_schema`.

### Field-level Hooks

When you define a field on an indexed type, ElasticGraph generates corresponding fields on several derived types
(filter input, aggregations, grouped-by, highlights, sub-aggregations) plus enum values on the sort order enum.
[`on_each_generated_schema_element`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#on_each_generated_schema_element-instance_method)
applies the same customization to all of them at once:

{% include copyable_code_snippet.html language="ruby" code='schema.object_type "Transaction" do |t|
  t.field "currency", "String" do |f|
    f.on_each_generated_schema_element do |element|
      element.directive "deprecated"
    end
  end
  t.index "transactions"
end' %}

To target a single derived form, use the more specific siblings:
[`customize_filter_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_filter_field-instance_method),
[`customize_aggregated_values_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_aggregated_values_field-instance_method),
[`customize_grouped_by_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_grouped_by_field-instance_method),
[`customize_highlights_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_highlights_field-instance_method),
[`customize_sub_aggregations_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_sub_aggregations_field-instance_method),
and [`customize_sort_order_enum_values`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_sort_order_enum_values-instance_method).

### Type-level Hooks

To customize the derived types generated from an object or interface type as a whole, use
[`customize_derived_types`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/Mixins/HasDerivedGraphQLTypeCustomizations.html#customize_derived_types-instance_method)
or [`customize_derived_type_fields`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/Mixins/HasDerivedGraphQLTypeCustomizations.html#customize_derived_type_fields-instance_method).
For example, to mark every derived type for `Campaign` with `@deprecated`:

{% include copyable_code_snippet.html language="ruby" code='schema.object_type "Campaign" do |t|
  t.customize_derived_types :all do |dt|
    dt.directive "deprecated"
  end
  t.index "campaigns"
end' %}

### Built-in Types

ElasticGraph generates several built-in types you don't define directly (`Query`, `PageInfo`, `AggregationCountDetail`,
and others). [`on_built_in_types`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/API.html#on_built_in_types-instance_method)
runs your block on each one as it's generated:

{% include copyable_code_snippet.html language="ruby" code='schema.on_built_in_types do |type|
  type.append_to_documentation "This is a built-in ElasticGraph type."
end' %}

## Customizing the Root `Query` Type

[`on_root_query_type`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/API.html#on_root_query_type-instance_method)
is a specialization of `on_built_in_types` that fires only for the root `Query` type. Use it to add ad hoc fields
to `Query`, append documentation, or apply directives:

{% include copyable_code_snippet.html language="ruby" code='schema.on_root_query_type do |t|
  t.append_to_documentation "Generated by ElasticGraph."
end' %}

This is also the hook you use to declare custom resolver fields on `Query`. See the
[Custom Resolvers guide]({% link guides/custom-graphql-resolvers.md %}) for an end-to-end example.

## Namespace Types

By default, the root query fields ElasticGraph generates for an indexed type are added directly to `Query`. For
example, an indexed `Widget` type produces `Query.widgets` and `Query.widgetAggregations`.

When ElasticGraph is composed into a federated supergraph alongside other subgraphs, `Query` can become crowded
and fields from different subgraphs can collide. A _namespace type_ lets you group ElasticGraph's root query fields
under a nested path; for example, `Query.olap.widgets` instead of `Query.widgets`. This can improve discoverability
and isolation of domain-specific types.

A namespace is an object type declared with [`namespace_type`](/elasticgraph/api-docs/main/ElasticGraph/SchemaDefinition/API.html#namespace_type-instance_method).
You can route an indexed type's root fields to the namespace by passing `on:` to [`root_query_fields`](/elasticgraph/api-docs/main/ElasticGraph/SchemaDefinition/Mixins/HasIndices.html#root_query_fields-instance_method),
then expose the namespace type as a field on `Query`.

{% include copyable_code_snippet.html language="ruby" data="namespaced_queries.files.schema_rb" %}

The namespace type is named `OlapQuery` and is exposed as the `olap` field on `Query`. This produces a GraphQL
API where `Widget`s are queried through `olap`:

{% include copyable_code_snippet.html language="graphql" data="namespaced_queries_queries.basic.QueryWidgets" %}

You don't need to wire up a resolver for `Query.olap`. ElasticGraph auto-resolves any no-argument field whose
return type is a namespace type.

### Nested Namespaces

Namespace types can be nested inside other namespace types. The same auto-resolution applies, so you don't have
to configure a resolver for any intermediate field.

{% include copyable_code_snippet.html language="ruby" data="nested_namespaced_queries.files.schema_rb" %}

Widgets are now queried at `Query.olap.domain.widgets`.
