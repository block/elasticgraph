---
layout: markdown
title: Custom GraphQL Resolvers
permalink: /guides/custom-graphql-resolvers/
nav_title: Custom Resolvers
menu_order: 20
---

Many GraphQL frameworks require you to write resolvers for each field. ElasticGraph works differently: it
defines a full set of resolvers for you. Simply define your schema and index your data, and it provides the
full GraphQL API.

However, the GraphQL API provided by ElasticGraph won't meet every need. Custom resolvers allow you to augment
the API provided by ElasticGraph with your own custom implementation. Here's how to define a custom resolver.

{: .alert-tip}
**Tip**{: .alert-title}
ElasticGraph provides friendly error messages. Instead of reading this guide, you can jump straight to
[step 3](#step-3-assign-the-resolver-to-a-field) and let the error messages guide you through the
changes explained in steps 1 and 2.

### Step 1: Define a Resolver Class

{% include copyable_code_snippet.html language="ruby" data="custom_resolver.snippets.lib.roll_dice_resolver_rb.RollDiceResolver" %}

Conventionally, resolvers are defined in `lib` (and you'd put `lib` on the Ruby `$LOAD_PATH`).
As shown here, the resolver needs to define two methods:

{% comment %}
TODO: link to the API docs for the different `ElasticGraph::GraphQL` types once the site includes those API docs.
{% endcomment %}

`initialize`
: Defines constructor logic. Accepts two arguments:
  * `elasticgraph_graphql`: the `ElasticGraph::GraphQL` instance, providing access to dependencies.
  * `config`: parameterized configuration values for your resolver.

`resolve`
: Defines the resolver logic. Accepts four arguments:
  * `field`: the `ElasticGraph::GraphQL::Schema::Field` object representing the field being resolved.
  * `object`: the value returned by the resolver of the parent field.
  * `args`: arguments passed in the query.
  * `context`: a hash-like object provided by the [GraphQL gem](https://graphql-ruby.org/queries/executing_queries.html#context)
    that is scoped to the execution of a single query.

{: .alert-note}
**Note**{: .alert-title}
There's a fifth optional argument: `lookahead`. It is a [`GraphQL::Execution::Lookahead` object](https://graphql-ruby.org/queries/lookahead.html)
which allows you to inspect the child field selections. However, providing it imposes some measurable overhead, and query resolution will be
more performant if you omit it from your `resolve` definition.

In this case, our `RollDiceResolver` simulates the rolling of the configured `number_of_dice`, each of which has a number of `sides`
provided as a query argument.

### Step 2: Register the Resolver

{% include copyable_code_snippet.html language="ruby" data="custom_resolver.snippets.schema_rb.register_graphql_resolver" %}

Custom resolvers must be registered with ElasticGraph in the schema definition, using the [`register_graphql_resolver`
API](https://block.github.io/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/API.html#register_graphql_resolver-instance_method).
Any arguments provided after `defined_at:` get recorded as resolver config, which will later be passed to the resolver's `initialize` method.
In this case, we've registered the resolver to roll two dice.

### Step 3: Assign the Resolver to a Field

{% include copyable_code_snippet.html language="ruby" data="custom_resolver.snippets.schema_rb.on_root_query_type" %}

Here we've defined a field on `Query` using [`on_root_query_type`](https://block.github.io/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/API.html#on_root_query_type-instance_method).
We've assigned the `:roll_dice` resolver to our custom field.

### Step 4: Query the Custom Field

That's all there is to it! With this custom resolver wired up, we can query the custom field:

{% include copyable_code_snippet.html language="graphql" data="custom_resolver.files.query_graphql" %}

