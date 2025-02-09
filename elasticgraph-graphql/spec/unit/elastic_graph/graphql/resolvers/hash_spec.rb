# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/hash"
require_relative "hash_or_document_shared_examples"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe Hash, :capture_logs, :resolver do
        include_examples "Hash or Document resolver"
      end
    end
  end
end
