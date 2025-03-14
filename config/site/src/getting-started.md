---
layout: markdown
title: Getting Started with ElasticGraph
permalink: /getting-started/
---

Welcome to ElasticGraph! This guide will help you set up ElasticGraph locally, run queries using GraphiQL, and evolve an example schema.
By the end of this tutorial, you'll have a working ElasticGraph instance running on your machine.

**Estimated Time to Complete**: Approximately 10 minutes

## Prerequisites

Before you begin, ensure you have the following installed on your system:

- **Docker** and **Docker Compose**
- **Ruby** (version 3.3 or higher)
- **Git**

Confirm these are installed using your terminal:

{% highlight shell %}
$ ruby -v
ruby 3.4.1 (2024-12-25 revision 48d4efcb85) +PRISM [arm64-darwin24]
$ docker compose version
Docker Compose version v2.32.4-desktop.1
$ git -v
git version 2.46.0
{% endhighlight %}

Note: you don't need these exact versions (these are just examples). Your Ruby version does need to be 3.3.x or greater, though.

## Step 1: Bootstrap a new ElasticGraph Project

Run the following command in your terminal:

{% highlight shell %}
$ gem exec elasticgraph new path/to/project --datastore elasticsearch
# or
$ gem exec elasticgraph new path/to/project --datastore opensearch
{% endhighlight %}

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

{% highlight shell %}
$ cd path/to/project
$ bundle exec rake boot_locally
{% endhighlight %}

This will:

* Boot the datastore (Elasticsearch or OpenSearch) using Docker
* Configure the datastore using the dumped `datastore_config.yaml` schema artifact
* Index some randomly generated artists/albums/tours/shows/venues data
* Boot ElasticGraph and a [GraphiQL UI](https://github.com/graphql/graphiql)
* [Open the GraphiQL UI](http://localhost:9393/) in your browser

Run some example queries in GraphiQL to confirm it's working. Here's an example query to get you started:

{% highlight graphql %}
{{ site.data.music_queries.filtering.FindArtistsFormedIn90s }}
{% endhighlight %}

Visit the [Query API docs]({% link query-api/overview.md %}) for other example queries that work against the example schema.

## Step 3: Add a new field to the Schema

If this is your first ElasticGraph project, we recommend you add a new field to the
example schema to get a feel for how it works. (Feel free to skip this step if you've
worked in an ElasticGraph project before).

Let's add a `Venue.yearOpened` field to our schema. Here's a git diff showing what to change:

{% highlight diff %}
diff --git a/config/schema/artists.rb b/config/schema/artists.rb
index 77e63de..7999fe4 100644
--- a/config/schema/artists.rb
+++ b/config/schema/artists.rb
@@ -56,6 +56,9 @@ ElasticGraph.define_schema do |schema|
   schema.object_type "Venue" do |t|
     t.field "id", "ID"
     t.field "name", "String"
+    t.field "yearOpened", "Int" do |f|
+      f.json_schema minimum: 1900, maximum: 2100
+    end
     t.field "location", "GeoLocation"
     t.field "capacity", "Int"
     t.relates_to_many "featuredArtists", "Artist", via: "tours.shows.venueId", dir: :in, singular: "featuredArtist"
{% endhighlight %}

Next, rebuild the project:

{% highlight shell %}
$ bundle exec rake build
{% endhighlight %}

This will re-generate the schema artifacts, run the test suite, and fail. The failing test will indicate
that the `:venue` factory is missing the new field. To fix it, define `yearOpened` on the `:venue` factory in the `factories.rb` file under `lib`:

{% highlight diff %}
diff --git a/lib/my_eg_project/factories.rb b/lib/my_eg_project/factories.rb
index 0d8659c..509f274 100644
--- a/lib/my_eg_project/factories.rb
+++ b/lib/my_eg_project/factories.rb
@@ -95,6 +95,7 @@ FactoryBot.define do
       "#{city_name} #{venue_type}"
     end

+    yearOpened { Faker::Number.between(from: 1900, to: 2025) }
     location { build(:geo_location) }
     capacity { Faker::Number.between(from: 200, to: 100_000) }
   end
{% endhighlight %}

Re-run `bundle exec rake build` and everything should pass. You can also run `bundle exec rake boot_locally`
and query your new field to confirm the fake values being generated for it.

## Next Steps

Congratulations! You've set up ElasticGraph locally and run your first queries. Here are some next steps you can take.

### Replace the Example Schema

Delete the `artist` schema definition:

{% highlight shell %}
$ rm config/schema/artists.rb
{% endhighlight %}

Then define your own schema in a Ruby file under `config/schema`.

* Use the [schema definition API docs](/elasticgraph/docs/main/ElasticGraph/SchemaDefinition/API.html) as a reference.
* Run `bundle exec rake build` and deal with any errors that are reported.
* Hint: search the project codebase for `TODO` comments to find things that need updating.

### Setup a CI Build

Your ElasticGraph project includes a command that's designed to be run on CI:

{% highlight shell %}
$ bundle exec rake check
{% endhighlight %}

This should be run on every commit (ideally before merging a pull request) using a CI system
such as [GitHub Actions](https://github.com/features/actions), [Buildkite](http://buildkite.com/),
or [Circle CI](https://circleci.com/).

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

- **[ElasticGraph Query API Documentation]({% link query-api/overview.md %})**
- **[ElasticGraph Ruby API Documentation]({{ '/docs/' | append: site.data.doc_versions.latest_version | relative_url }})**
- **[GraphQL Introduction](https://graphql.org/learn/)**

## Feedback

We'd love to hear your feedback. If you encounter any issues or have suggestions, please start a discussion in
our [discord channel](https://discord.gg/8m9FqJ7a7F) or on [GitHub](https://github.com/block/elasticgraph/discussions).

---

*Happy coding with ElasticGraph!*
