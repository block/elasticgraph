# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    # Represents a client of an ElasticGraph GraphQL endpoint.
    # `name` and `source_description` can really be any string, but `name` is
    # meant to be a friendly/human readable string (such as a service name)
    # where as `source_description` is meant to be an opaque string describing
    # where `name` came from.
    class Client < Data.define(:source_description, :name)
      # `Data.define` provides the following methods:
      # @dynamic initialize, name, source_description, with

      ANONYMOUS = new("(anonymous)", "(anonymous)")
      ELASTICGRAPH_INTERNAL = new("(ElasticGraphInternal)", "(ElasticGraphInternal)")

      def description
        if source_description == name
          name
        else
          "#{name} (#{source_description})"
        end
      end

      # Default resolver used to determine the client for a given HTTP request.
      # Also defines the interface of a client resolver. (This is why we define `initialize`).
      class DefaultResolver
        def initialize(config)
        end

        def resolve(http_request)
          Client::ANONYMOUS
        end
      end
    end
  end
end
