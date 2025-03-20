# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class DatastoreCore
    module Configuration
      class ClientFaradayAdapter < ::Data.define(
        # The faraday adapter to use with the datastore client, such as `httpx` or `typhoeus`.
        # For more info, see:
        # https://github.com/elastic/elasticsearch-ruby/commit/a7bbdbf2a96168c1b33dca46ee160d2d4d75ada0
        :name,
        # A Ruby library to require which provides the named adapter (optional).
        :require
      )
        def self.from_parsed_yaml(parsed_yaml)
          parsed_yaml = parsed_yaml.fetch("client_faraday_adapter") || {}
          extra_keys = parsed_yaml.keys - EXPECTED_KEYS

          unless extra_keys.empty?
            raise Errors::ConfigError, "Unknown `datastore.client_faraday_adapter` config settings: #{extra_keys.join(", ")}"
          end

          new(
            name: parsed_yaml["name"]&.to_sym,
            require: parsed_yaml["require"]
          )
        end

        EXPECTED_KEYS = members.map(&:to_s)
      end
    end
  end
end
