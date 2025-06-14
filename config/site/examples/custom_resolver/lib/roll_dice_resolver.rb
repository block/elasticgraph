# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# :snippet-start: RollDiceResolver
# in lib/roll_dice_resolver.rb
class RollDiceResolver
  def initialize(elasticgraph_graphql:, config:)
    @number_of_dice = config.fetch(:number_of_dice)
    @multiplier = config.fetch(:multiplier)
  end

  def resolve(field:, object:, args:, context:)
    @number_of_dice
      .times
      .map { rand(args.fetch("sides")) + 1 }
      .sum * @multiplier
  end
end
# :snippet-end:
