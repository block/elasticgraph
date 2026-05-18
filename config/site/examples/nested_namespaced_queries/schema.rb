ElasticGraph.define_schema do |schema|
  schema.json_schema_version 1

  schema.namespace_type "OlapQuery" do |t|
    t.field "domain", "DomainQuery"
  end

  schema.namespace_type "DomainQuery"

  schema.on_root_query_type do |t|
    t.field "olap", "OlapQuery"
  end

  schema.object_type "Widget" do |t|
    t.field "id", "ID"
    t.index "widgets"
    t.root_query_fields plural: "widgets", on: "DomainQuery"
  end
end
