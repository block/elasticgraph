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

The customizations primarily fall into two groups:

- **Naming options** are passed to [`Local::RakeTasks`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html)
  in your `Rakefile`. They control the casing and spelling of generated names without changing schema structure.
- **Schema definition hooks** let you customize generated types and fields; adding directives, documentation, or 
  grouping fields under namespace types.

## Casing of Generated Fields

Set [`schema_element_name_form`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#schema_element_name_form-instance_method)
to choose between `:camelCase` (the default) and `:snake_case` for every generated field name, argument name, and
directive name in the SDL. Generated types like `WidgetFilterInput` are unaffected; only the elements within them.

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.rake_task_examples_rb.schema_element_name_form" %}

For example, this will cause ElasticGraph to generate `StringFilterInput.equal_to_any_of` rather than
`StringFilterInput.equalToAnyOf`.

{: .alert-note}
**Note**{: .alert-title}
This option only impacts names originated by ElasticGraph. If you configure `:snake_case` but then define a `homeCity` 
field, ElasticGraph will use the name `homeCity` rather than `home_city` on the types it derives from your definition.

## Renaming Generated Fields, Arguments, and Directives

Use [`schema_element_name_overrides`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#schema_element_name_overrides-instance_method)
to rename individual generated fields, arguments, or directives. For example, to spell out filter operators that ElasticGraph abbreviates by default:

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.rake_task_examples_rb.schema_element_name_overrides" %}

To rename specific values within a generated enum (e.g. `DayOfWeek.MONDAY` to `DayOfWeek.MON`), use
[`enum_value_overrides_by_type`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#enum_value_overrides_by_type-instance_method).

## Naming Formats for Derived Types

For each type, ElasticGraph derives a number of other types. For example, if you define a `Widget` indexed type, ElasticGraph will derive
types like `WidgetFilterInput`, `WidgetAggregation`, and `WidgetSortOrder`. These type naming patterns are configured by
[`derived_type_name_formats`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#derived_type_name_formats-instance_method).

For example, to drop the `Input` suffix from types like `WidgetFilterInput` across the entire schema:

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.rake_task_examples_rb.derived_type_name_formats" %}

The full set of naming formats is documented at
[`SchemaElements::TypeNamer::DEFAULT_FORMATS`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/TypeNamer.html#DEFAULT_FORMATS-constant).
The `%{base}` placeholder is replaced with the source type's name; format strings must preserve every placeholder
the default uses, or schema generation fails with a config error.

## Renaming Individual Types

When you need to rename a single type rather than changing a naming format used across the entire schema—for example, swapping ElasticGraph's `JsonSafeLong`
scalar for one with a name your team prefers—use [`type_name_overrides`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/Local/RakeTasks.html#type_name_overrides-instance_method):

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.rake_task_examples_rb.type_name_overrides" %}

{: .alert-warning}
**Warning**{: .alert-title}
The standard GraphQL scalars (`Boolean`, `Float`, `ID`, `Int`, `String`) and the root `Query` type cannot be renamed
this way.

## Customization Hooks

The schema definition API exposes hooks that let you customize generated types and fields. These hooks are commonly used
to add directives like `@deprecated`. Hooks are available on individual fields, individual types, and on the schema itself.

### Field-level Hooks

When you define a field, ElasticGraph generates corresponding fields on several derived types (filter input, aggregations, 
grouped-by, highlights, sub-aggregations) plus enum values on the sort order enum. [`on_each_generated_schema_element`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#on_each_generated_schema_element-instance_method)
applies the same customization to all of them at once:

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.schema_rb.on_each_generated_schema_element" %}

In this case, a `@deprecated` directive would be added to `Transaction.currency`, as well as all the schema elements
derived from `Transaction.currency` including `TransactionFilterInput.currency`, `TransactionGroupedBy.currency`, and several others.

To target a single derived form, use the more specific hooks:

* [`customize_filter_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_filter_field-instance_method)
* [`customize_aggregated_values_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_aggregated_values_field-instance_method)
* [`customize_grouped_by_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_grouped_by_field-instance_method)
* [`customize_highlights_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_highlights_field-instance_method)
* [`customize_sub_aggregations_field`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_sub_aggregations_field-instance_method)
* [`customize_sort_order_enum_values`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/SchemaElements/Field.html#customize_sort_order_enum_values-instance_method)

### Type-level Hooks

To customize the derived types generated from an object or interface type as a whole, use
[`customize_derived_types`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/Mixins/HasDerivedGraphQLTypeCustomizations.html#customize_derived_types-instance_method).
Pass `:all` to customize every derived type. For example, to mark every derived type for `Campaign` with `@deprecated`:

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.schema_rb.customize_derived_types_all" %}

Or pass one or more specific type names to target just those derived types:

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.schema_rb.customize_derived_types_named" %}

To customize specific fields on a derived type, use
[`customize_derived_type_fields`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/Mixins/HasDerivedGraphQLTypeCustomizations.html#customize_derived_type_fields-instance_method).
For example, to deprecate `pageInfo` and `totalEdgeCount` on `ProductConnection`:

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.schema_rb.customize_derived_type_fields" %}

### Built-in Types

ElasticGraph generates several built-in types you don't define directly (`Query`, `PageInfo`, `AggregationCountDetail`,
and others). [`on_built_in_types`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/API.html#on_built_in_types-instance_method)
runs your block on each one as it's generated:

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.schema_rb.on_built_in_types" %}

## Customizing the Root `Query` Type

[`on_root_query_type`](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/API.html#on_root_query_type-instance_method)
is a specialization of `on_built_in_types` that fires only for the root `Query` type. Use it to add ad hoc fields
to `Query`, append documentation, or apply directives:

{% include copyable_code_snippet.html language="ruby" data="schema_customization.snippets.schema_rb.on_root_query_type" %}

You can also use this hook to add custom `Query` fields that use a [custom GraphQL resolver]({% link guides/custom-graphql-resolvers.md %}).

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

{% include copyable_code_snippet.html language="ruby" data="namespaced_queries.snippets.schema_rb.namespace_type" %}

The namespace type is named `OlapQuery` and is exposed as the `olap` field on `Query`. This produces a GraphQL
API where `Widget`s are queried through `olap`:

{% include copyable_code_snippet.html language="graphql" data="namespaced_queries_queries.basic.QueryWidgets" %}

You don't need to wire up a resolver for `Query.olap`. ElasticGraph auto-resolves any no-argument field whose
return type is a namespace type.

### Nested Namespaces

Namespace types can be nested inside other namespace types. The same auto-resolution applies, so you don't have
to configure a resolver for any intermediate field.

{% include copyable_code_snippet.html language="ruby" data="nested_namespaced_queries.snippets.schema_rb.nested_namespace_type" %}

Widgets are now queried at `Query.olap.domain.widgets`.
