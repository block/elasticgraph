# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module StubDatastoreClient
    def datastore_client
      @datastore_client ||= stubbed_datastore_client
    end

    def stubbed_datastore_client(**additional_stubs)
      instance_double(
        "ElasticGraph::Elasticsearch::Client",
        # Here we stub methods that are called from `DatastoreCore` index definitions, so that our unit specs
        # can use index definitions without worrying about datastore calls they will make.
        list_indices_matching: [],
        # `searches_could_hit_incomplete_docs?` calls these. It's tricky to provide an accurate full configuration
        # here but it only looks at a tiny part of the config, and falls back to `current_sources` so we can safely
        # stub it with an empty hash.
        get_index: {},
        get_index_template: {},
        **additional_stubs
      )
    end
  end

  RSpec.configure do |c|
    c.include StubDatastoreClient, :stub_datastore_client
  end
end
