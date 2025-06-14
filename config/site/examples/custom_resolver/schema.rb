# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

$LOAD_PATH << ::File.join(__dir__, "lib")

ElasticGraph.define_schema do |schema|
  schema.json_schema_version 1

  # :snippet-start: register_graphql_resolver
  require(require_path = "roll_dice_resolver")
  schema.register_graphql_resolver :roll_dice,
    RollDiceResolver,
    defined_at: require_path,
    number_of_dice: 2
  # :snippet-end:

  # :snippet-start: on_root_query_type
  schema.on_root_query_type do |t|
    t.field "rollDice", "Int" do |f|
      f.argument "sides", "Int" do |a|
        a.default 6
      end
      f.resolve_with :roll_dice, multiplier: 3
    end
  end
  # :snippet-end:
end
