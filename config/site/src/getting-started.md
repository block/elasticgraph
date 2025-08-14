---
layout: markdown
title: Getting Started with ElasticGraph
permalink: /getting-started/
---

Welcome to ElasticGraph! This guide will help you set up ElasticGraph locally, run queries using GraphiQL, and evolve an example schema.
By the end of this tutorial, you'll have a working ElasticGraph instance running on your machine.

**Estimated Time to Complete**: 10 minutes

## Prerequisites

Before you begin, ensure you have the following installed on your system:

- **Docker** and **Docker Compose**
- **Ruby** (version 3.4 or higher)
- **Git**

Confirm these are installed using your terminal:

{% include copyable_code_snippet.html language="shell" code="$ ruby -v
ruby 3.4.2 (2025-02-15 revision d2930f8e7a) +PRISM [arm64-darwin24]
$ docker compose version
Docker Compose version v2.32.4-desktop.1
$ git -v
git version 2.46.0" %}

{: .alert-note}
**Note**{: .alert-title}
You don't need these exact versions (these are just examples). Your Ruby version does need to be 3.4.x or greater, though.

## Step 1: Bootstrap a new ElasticGraph Project

Run one of the following commands in your terminal:

{% include copyable_code_snippet.html language="shell" code="gem exec elasticgraph new path/to/project --datastore elasticsearch" %}
{% include copyable_code_snippet.html language="shell" code="gem exec elasticgraph new path/to/project --datastore opensearch" %}

{: .alert-note}
**Note**{: .alert-title}
Not sure whether to use Elasticsearch or OpenSearch? We recommend using whichever has better
support in your organization. ElasticGraph works identically with both, and the choice makes
no difference in the tutorial that follows.

This will:

* Generate a project skeleton with an example schema
* Install dependencies including the latest version of ElasticGraph itself
* Dump schema artifacts
* Run the build tasks (including your new project's test suite)
* Initialize the project as a git repository
* Commit the initial setup

## Step 2: Boot Locally

The initial project skeleton comes with everything you need to run ElasticGraph locally.
Confirm it works by running the following:

{% include copyable_code_snippet.html language="shell" code="cd path/to/project && bundle exec rake boot_locally" %}

This will:

* Boot the datastore (Elasticsearch or OpenSearch) using Docker
* Configure the datastore using the dumped `datastore_config.yaml` schema artifact
* Index some randomly generated artists/albums/tours/shows/venues data
* Boot ElasticGraph and a [GraphiQL UI](https://github.com/graphql/graphiql)
* Open the [local GraphiQL UI]({{ site.localhost_eg_url }}) in your browser

Run some example queries in GraphiQL to confirm it's working. Here's an example query to get you started:

{% include copyable_code_snippet.html language="graphql" data="music_queries.filtering.FindArtistsFormedIn90s" %}

Visit the [Query API docs]({% link query-api.md %}) for other example queries that work against the example schema.

## Step 3: Add a new field to the Schema

If this is your first ElasticGraph project, we recommend you add a new field to the
example schema to get a feel for how it works. (Feel free to skip this step if you've
worked in an ElasticGraph project before).

Let's add a `Venue.yearOpened` field to our schema. Here's a git diff showing what to change:

{% include copyable_code_snippet.html language="diff" code="diff --git a/config/schema/artists.rb b/config/schema/artists.rb
index 77e63de..7999fe4 100644
--- a/config/schema/artists.rb
+++ b/config/schema/artists.rb
@@ -56,6 +56,9 @@ ElasticGraph.define_schema do |schema|
   schema.object_type \"Venue\" do |t|
     t.field \"id\", \"ID\"
     t.field \"name\", \"String\"
+    t.field \"yearOpened\", \"Int\" do |f|
+      f.json_schema minimum: 1900, maximum: 2100
+    end
     t.field \"location\", \"GeoLocation\"
     t.field \"capacity\", \"Int\"
     t.relates_to_many \"featuredArtists\", \"Artist\", via: \"tours.shows.venueId\", dir: :in, singular: \"featuredArtist\"" %}

Next, rebuild the project:

{% include copyable_code_snippet.html language="shell" code="bundle exec rake" %}

This will re-generate the schema artifacts, run the test suite, and fail. The failing test will indicate
that the `:venue` factory is missing the new field. To fix it, define `yearOpened` on the `:venue` factory in the `factories.rb` file under `lib`:

{% include copyable_code_snippet.html language="diff" code="diff --git a/lib/my_eg_project/factories.rb b/lib/my_eg_project/factories.rb
index 0d8659c..509f274 100644
--- a/lib/my_eg_project/factories.rb
+++ b/lib/my_eg_project/factories.rb
@@ -95,6 +95,7 @@ FactoryBot.define do
       \"#{city_name} #{venue_type}\"
     end

+    yearOpened { Faker::Number.between(from: 1900, to: 2025) }
     location { build(:geo_location) }
     capacity { Faker::Number.between(from: 200, to: 100_000) }
   end" %}

Re-run `bundle exec rake` and everything should pass. You can also run `bundle exec rake boot_locally`
and query your new field to confirm the random values being generated for it.

## Next Steps

Congratulations! You've set up ElasticGraph locally and run your first queries. Here are some next steps you can take.

### Replace the Example Schema

Delete the `artist` schema definition:

{% include copyable_code_snippet.html language="shell" code="rm config/schema/artists.rb" %}

Then define your own schema in a Ruby file under `config/schema`.

* Use the [schema definition API docs](/elasticgraph/api-docs/{{ site.data.doc_versions.latest_version }}/ElasticGraph/SchemaDefinition/API.html) as a reference.
* Use our [AI Tools]({% link guides/ai-tools.md %}) together with an AI agent such as [Goose](https://block.github.io/goose/) to translate a schema from an existing format such as protocol buffers, JSON schema, or SQL.
* Run `bundle exec rake` and deal with any errors that are reported.
* Hint: search the project codebase for `TODO` comments to find things that need updating.

### Setup a CI Build

Your ElasticGraph project includes a command that's designed to be run on CI:

{% include copyable_code_snippet.html language="shell" code="bundle exec rake check" %}

This should be run on every commit (ideally before merging a pull request) using a CI system
such as [Buildkite](https://buildkite.com/), [Circle CI](https://circleci.com/),
[GitHub Actions](https://github.com/features/actions), or [Jenkins](https://www.jenkins.io/).

### Deploy

ElasticGraph can be deployed in two different ways:

* As a standard Ruby [Rack](https://github.com/rack/rack) application using [elasticgraph-rack](https://github.com/block/elasticgraph/tree/main/elasticgraph-rack).
  Similar to a [Rails](https://rubyonrails.org/) or [Sinatra](https://sinatrarb.com/) app, you can serve ElasticGraph from
  [any of the webservers](https://github.com/rack/rack#supported-web-servers) that support the Rack spec. Or you could mount your
  ElasticGraph GraphQL endpoint inside an existing Rails or Sinatra application!
* As a serverless application in AWS using [elasticgraph-graphql_lambda](https://github.com/block/elasticgraph/tree/main/elasticgraph-graphql_lambda).

### Connect a Real Data Source

Finally, you'll want to publish into your deployed ElasticGraph project from a real data source. The generated `json_schemas.yaml` artifact
can be used in your publishing system to validate the indexing payloads or for code generation (using a project like
[json-kotlin-schema-codegen](https://github.com/pwall567/json-kotlin-schema-codegen)).

## Resources

- **[How ElasticGraph Works]({% link guides/how-it-works.md %})**
- **[GraphQL Introduction](https://graphql.org/learn/)**
- **[ElasticGraph Query API Documentation]({% link query-api.md %})**
- **[ElasticGraph Guides]({% link guides.md %})**
- **[ElasticGraph Ruby API Documentation]({% link api-docs.md %})**

## Feedback

We'd love to hear your feedback. If you encounter any issues or have suggestions, please start a discussion in
the `#elasticgraph` channel on the [Block Open Source Discord server](https://discord.gg/block-opensource) or on
[GitHub](https://github.com/block/elasticgraph/discussions).

---

*Happy coding with ElasticGraph!*
