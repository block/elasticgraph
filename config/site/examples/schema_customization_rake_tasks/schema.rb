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

  schema.object_type "Widget" do |t|
    t.field "id", "ID"
    t.field "name", "String"
    t.index "widgets"
  end
end
