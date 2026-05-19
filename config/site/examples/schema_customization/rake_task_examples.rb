# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file contains Rakefile-style examples that get rendered into the
# "Customizing the GraphQL Schema" guide. The code is not executed on its own;
# the surrounding example exercises Local::RakeTasks via the site Rakefile.

# :snippet-start: schema_element_name_form
ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/local.yaml",
  path_to_schema: "config/schema.rb"
) do |tasks|
  tasks.schema_element_name_form = :snake_case
end
# :snippet-end:

# :snippet-start: schema_element_name_overrides
ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/local.yaml",
  path_to_schema: "config/schema.rb"
) do |tasks|
  tasks.schema_element_name_overrides = {
    gt: "greaterThan",
    gte: "greaterThanOrEqualTo",
    lt: "lessThan",
    lte: "lessThanOrEqualTo"
  }
end
# :snippet-end:

# :snippet-start: derived_type_name_formats
ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/local.yaml",
  path_to_schema: "config/schema.rb"
) do |tasks|
  tasks.derived_type_name_formats = {FilterInput: "%{base}Filter"}
end
# :snippet-end:

# :snippet-start: type_name_overrides
ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/local.yaml",
  path_to_schema: "config/schema.rb"
) do |tasks|
  tasks.type_name_overrides = {JsonSafeLong: "BigInt"}
end
# :snippet-end:
