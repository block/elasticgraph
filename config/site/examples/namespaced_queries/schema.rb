# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

ElasticGraph.define_schema do |schema|
  schema.json_schema_version 1
  schema.enforce_json_schema_version false
end

# :snippet-start: namespace_type
ElasticGraph.define_schema do |schema|
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
# :snippet-end:
