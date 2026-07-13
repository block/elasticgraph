---
layout: markdown
title: What is ElasticGraph?
permalink: /about/
---

ElasticGraph is a general purpose, near real-time data query and search platform that is scalable and performant, serves rich interactive queries, and dramatically simplifies the creation of complex reports. The platform combines the power of indexing and search of Elasticsearch or OpenSearch with the query flexibility of the GraphQL language. Optimized for the AWS cloud, it also offers scale and reliability.

ElasticGraph is a naturally flexible framework with many different possible applications. However, the main motivation we have for building it is to power various data APIs, UIs and reports. These modern reports require filtering and aggregations across a body of ever-growing data sets. Modern APIs allow us to:

- Minimize network trips to retrieve your data
- Get exactly what you want in a single query. No over- or under-serving the data.
- Push filtering and complex calculations to the backend.

## What can I do with it?

The ElasticGraph platform will allow you to query your data in many different configurations. To do so requires defining a schema which ElasticGraph will use to both index data and also query it. Besides all basic GraphQL query features, ElasticGraph also supports:

- Real-time indexing and data querying
- Filtering, sorting, pagination, grouping, aggregations, and sub-aggregations
- Navigating across data sets in a single query
- Robust, safe schema evolution support via the Query Registry mechanism
- Derived indexes to power commonly accessed queries and aggregations
- Client and Publisher libraries

## Get started

Our [Getting Started guide]({% link getting-started.md %}) will help you get up and running in about 10 minutes.
