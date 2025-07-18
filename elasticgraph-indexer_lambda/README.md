# ElasticGraph::IndexerLambda

Adapts elasticgraph-indexer to run in an AWS Lambda.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-indexer_lambda["elasticgraph-indexer_lambda"];
    class elasticgraph-indexer_lambda targetGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer_lambda --> elasticgraph-indexer;
    class elasticgraph-indexer otherEgGemStyle;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-indexer_lambda --> elasticgraph-lambda_support;
    class elasticgraph-lambda_support otherEgGemStyle;
    aws-sdk-s3["aws-sdk-s3"];
    elasticgraph-indexer_lambda --> aws-sdk-s3;
    class aws-sdk-s3 externalGemStyle;
    ox["ox"];
    elasticgraph-indexer_lambda --> ox;
    class ox externalGemStyle;
    click aws-sdk-s3 href "https://rubygems.org/gems/aws-sdk-s3" "Open on RubyGems.org" _blank;
    click ox href "https://rubygems.org/gems/ox" "Open on RubyGems.org" _blank;
```

## SQS Message Payload Format

We use [JSON Lines](http://jsonlines.org/) to encode our indexing events. It is just individual JSON objects
delimited by a newline control character(not the `\n` string sequence), such as:

```
{"op": "upsert", "__typename": "Payment", "id": "123", "version": "1", "record": {...} }
{"op": "upsert", "__typename": "Payment", "id": "123", "version": "2", record: {...} }
{"op": "delete", "__typename": "Payment", "id": "123", "version": "3"}
```

However, due to SQS message size limit, we have to batch our events carefully so each batch is below the size limit.
This makes payload encoding a bit more complicated on the publisher side because each message has a size limit.
The following code snippet respects the max message size limit and sends JSON Lines payloads with proper size:

```ruby
def partition_into_acceptably_sized_chunks(batch, max_size_per_chunk)
  chunk_size = 0
  batch
    .map { |item| JSON.generate(item) }
    .slice_before do |json|
      chunk_size += (json.bytesize + 1)
      (chunk_size > max_size_per_chunk).tap { |chunk_done| chunk_size = 0 if chunk_done }
     end
    .map { |chunk| chunk.join("\n") }
end
```
