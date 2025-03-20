# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin"
require "elastic_graph/lambda_support"

module ElasticGraph
  # @private
  module AdminLambda
    # Builds an `ElasticGraph::Admin` instance from our lambda ENV vars.
    def self.admin_from_env
      LambdaSupport.build_from_env(Admin)
    end
  end
end
