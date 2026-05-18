ElasticGraph.define_schema do |schema|
  schema.json_schema_version 1

  schema.namespace_type "OlapQuery"

  schema.on_root_query_type do |t|
    t.field "olap", "OlapQuery"
  end

  schema.object_type "Widget" do |t|
    t.field "id", "ID"
    t.field "name", "String"
    t.index "widgets"
    t.root_query_fields plural: "widgets", on: "OlapQuery"
  end
end
