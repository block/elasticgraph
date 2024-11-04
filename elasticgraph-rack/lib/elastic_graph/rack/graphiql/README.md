## GraphiQL for ElasticGraph

This directory provides the GraphiQL in browser UI for working with ElasticGraph
applications.

The `index.html` file is copied from:

https://github.com/graphql/graphiql/blob/graphiql%402.4.0/examples/graphiql-cdn/index.html

However, we've applied some slight changes to make it work for ElasticGraph.

```diff
diff --git a/elasticgraph-rack/lib/elastic_graph/rack/graphiql/index.html b/elasticgraph-rack/lib/elastic_graph/rack/graphiql/index.html
index 55cf5d05..a672ead9 100644
--- a/elasticgraph-rack/lib/elastic_graph/rack/graphiql/index.html
+++ b/elasticgraph-rack/lib/elastic_graph/rack/graphiql/index.html
@@ -8,7 +8,7 @@
 <!DOCTYPE html>
 <html lang="en">
   <head>
-    <title>GraphiQL</title>
+    <title>ElasticGraph GraphiQL</title>
     <style>
       body {
         height: 100%;
@@ -58,7 +58,7 @@
       ReactDOM.render(
         React.createElement(GraphiQL, {
           fetcher: GraphiQL.createFetcher({
-            url: 'https://swapi-graphql.netlify.app/.netlify/functions/index',
+            url: '/graphql',
           }),
           defaultEditorToolsVisibility: true,
         }),
```

## License

[index.html](index.html) comes from the [GraphiQL project](https://github.com/graphql/graphiql),
licensed under the MIT License, Copyright (c) GraphQL Contributors.
