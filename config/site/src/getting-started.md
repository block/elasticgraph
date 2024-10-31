---
layout: markdown
title: Getting Started with ElasticGraph
permalink: /getting-started/
---

Welcome to ElasticGraph! This guide will help you set up ElasticGraph locally, run queries using GraphiQL, and verify the datastore using the OpenSearch Dashboard. By the end of this tutorial, you'll have a working ElasticGraph instance running on your machine.

**Estimated Time to Complete**: Approximately 2 hours

## Prerequisites

Before you begin, ensure you have the following installed on your system:

- **Git**: For cloning repositories.
- **Docker**: For running services locally.
- **Ruby (version 3.2 or higher)** and **Bundler**: For running ElasticGraph scripts.
- **OpenSearch and Kibana**: Included in the Docker setup.

## Step 1: Clone the ElasticGraph Repository

Begin by cloning the ElasticGraph project template from GitHub:

```bash
git clone <COMING SOON>!
cd elasticgraph-project-template
```

## Step 2: Run the Initialization Script

We have an initialization script that sets up your ElasticGraph project with necessary configurations.

Run the following command in your terminal:

```bash
curl -sL https://raw.githubusercontent.com/<COMING-SOON>/elasticgraph-project-template/main/script/init_eg | bash -s
```

This script will prompt you for some inputs:

- **Application Name**: Choose a name for your ElasticGraph application.
- **Dataset Name**: Decide on a name for your dataset (e.g., `customers`).

The script will:

- Set up directory structures.
- Copy templated files.
- Install necessary dependencies.

## Step 3: Define Your Schema

ElasticGraph uses schemas to define the structure of your data.

You can skip this part for now if you want to play with the sample schema. Otherwise, follow these steps to define your own schema:

1. **Remove Sample Schema**:

   Delete the sample schema file:

   ```bash
   rm config/schema/people.rb
   ```

2. **Create Your Schema**:

   Create a new file in `config/schema/` named after your dataset, for example, `config/schema/customers.rb`.

   Define your schema in this file. Here's a basic example:

   ```ruby
    ElasticGraph.define_schema do |schema|
      schema.json_schema_version 1

      schema.object_type "Artist" do |t|
        t.field "id", "ID"
        t.field "name", "String"
        t.field "lifetimeSales", "Int"
        t.field "bio", "ArtistBio"

        t.field "albums", "[Album!]!" do |f|
          f.mapping type: "nested"
        end

        t.index "artists"
      end
    end

    # ...
   ```

3. **Update Configuration**:

   Ensure that your dataset is correctly referenced in your configuration files.

   - **config/settings/lambda.yaml**:

     Update or add your dataset name under the `datasets` section.

## Step 4: Build and Test Your Project

1. **Install Dependencies**:

   ```bash
   bundle install
   ```

2. **Run Rake Tasks**:

   Test your setup by running:

   ```bash
   bundle exec rake
   ```

   This command runs all the default tasks to ensure everything is configured correctly.

3. **Fix Any Issues**:

   If you encounter errors, follow the error message prompts to fix anything that isn't set up correctly.

## Step 5: Start ElasticGraph Locally

With Docker running, start your local ElasticGraph instance:

```bash
bundle exec rake boot_locally
```

This command will:

- Build Docker images for ElasticGraph and OpenSearch.
- Start the services using Docker Compose.
- Populate your dataset with fake data.
- Launch GraphiQL in your default web browser.

## Step 6: Use GraphiQL to Run Queries

GraphiQL is a graphical interactive in-browser GraphQL IDE.

Once GraphiQL opens in your browser, you can start running queries against your local ElasticGraph instance.

### Example Query

Replace `customers` and fields with those relevant to your schema.

```graphql
query Test {
  customers {
    totalEdgeCount
    nodes {
      id
      name
      email
    }
  }
}
```

**Explanation**:

- **customers**: The dataset you defined.
- **totalEdgeCount**: Returns the total number of records.
- **nodes**: An array of data nodes.
- **fields inside nodes**: The fields you've defined in your schema.

Learn more about ElasticGraph queries in the [Query API documentation]({{ '/query-api' | relative_url }}).

## Step 7: Access the OpenSearch Dashboard (aka Elasticsearch Kibana)

With `bundle exec rake boot_locally` still running:

1. **Open Dashboard**:

   Navigate to [http://localhost:5601](http://localhost:5601) in your web browser.

2. **Explore Your Data**:

   - Click on **"Dev Tools"** in the Kibana sidebar.
   - Run the following commands to explore your indices:

     ```elasticsearch
     GET /_cat/indices?v
     GET /_cat/shards?v
     GET /_cat/templates?v
     ```

3. **Search Your Data**:

   Replace `your-index-name` with the name of your index (usually your dataset name).

   ```elasticsearch
   GET /your-index-name/_search
   ```

   This will return all documents in your index. Normally you'll query via GraphiQL, but this is useful for debugging.


## Troubleshooting

- **Docker Issues**:

  - Ensure Docker is running.
  - If ports are already in use, stop other services or adjust the port settings in `docker-compose.yml`.

- **GraphiQL Not Loading**:

  - Verify that the local server is running.
  - Check for errors in the terminal where `boot_locally` is running.

- **Schema Errors**:

  - Ensure your schema files are correctly formatted.
  - Check for typos in field names and types.

- **Kibana Not Accessible**:

  - Confirm that Kibana is running (`docker ps` to see running containers).
  - Check if another service is using port `5601`.

## Next Steps

Congratulations! You've set up ElasticGraph locally and run your first queries.

- **Explore Advanced Features**:

  - Learn about custom resolvers.
  - Implement complex queries and mutations.

- **Connect to Real Data Sources**:

  - Replace fake data with real data ingestion pipelines.
  - Integrate with databases or APIs.

- **Contribute to ElasticGraph**:

  - Report issues or suggest features on GitHub.
  - Submit pull requests to improve the project.

## Resources

- **ElasticGraph Documentation**: [{{ '/docs/main' | absolute_url }}]({{ '/docs/main' | relative_url }})
- **GraphQL Introduction**: [https://graphql.org/learn/](https://graphql.org/learn/)
- **OpenSearch Documentation**: [https://opensearch.org/docs/latest/](https://opensearch.org/docs/latest/)

## Feedback

We'd love to hear your feedback. If you encounter any issues or have suggestions, please open an issue on our GitHub repository.

---

*Happy coding with ElasticGraph!*
