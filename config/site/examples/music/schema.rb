# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "pathname"

ElasticGraph.define_schema do |schema|
  schema.json_schema_version 1
end

Dir["#{__dir__}/schema/**/*.rb"].each do |schema_def_file|
  load Pathname(schema_def_file).expand_path
end
