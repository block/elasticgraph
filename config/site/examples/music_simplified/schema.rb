ElasticGraph.define_schema do |schema|
  schema.json_schema_version 1

  schema.object_type "Artist" do |t|
    t.field "id", "ID"
    t.field "name", "String"
    t.field "lifetimeSales", "JsonSafeLong"

    t.field "albums", "[Album!]!" do |f|
      f.mapping type: "nested"
    end

    t.index "artists"
  end

  schema.object_type "Album" do |t|
    t.field "name", "String"
    t.field "releasedOn", "Date"
  end
end
