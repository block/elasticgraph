# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/document"
require_relative "hash_or_document_shared_examples"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe Document, :capture_logs, :resolver do
        include_examples "Hash or Document resolver"

        def resolve(type_name, field_name, hash, **options)
          doc = DatastoreResponse::Document.with_payload(hash)
          super(type_name, field_name, doc, **options)
        end
      end
    end
  end
end
