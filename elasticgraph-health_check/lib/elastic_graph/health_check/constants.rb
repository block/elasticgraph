# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Enumerates constants that are used from multiple places in ElasticGraph::HealthCheck.
module ElasticGraph
  module HealthCheck
    # List of datastore cluster health fields from:
    # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/cluster-health.html#cluster-health-api-response-body
    #
    # This is expressed as a constant so that we can use it in dynamic ways in a few places
    # (such as in a test; we want an acceptance test to fetch all these fields to make
    # sure they work, and having them defined this way makes that easier).
    #
    # To get this list, this javascript was used in the chrome console:
    #
    # Array.from(document.querySelectorAll('div.variablelist')[2].querySelectorAll(':scope > dl.variablelist > dt')).map(x => x.innerText)
    #
    # (Feel free to use/change that as needed if/when you update this list in the future based on a newer datastore version.)
    #
    # Note: `discovered_master` is a new boolean field that AWS OpenSearch seems to add to the cluster health response.
    # It was observed on the response on 2022-04-18.
    DATASTORE_CLUSTER_HEALTH_FIELDS = %i[
      cluster_name
      status
      timed_out
      number_of_nodes
      number_of_data_nodes
      active_primary_shards
      active_shards
      relocating_shards
      initializing_shards
      unassigned_shards
      delayed_unassigned_shards
      number_of_pending_tasks
      number_of_in_flight_fetch
      task_max_waiting_in_queue_millis
      active_shards_percent_as_number
      discovered_master
    ].to_set
  end
end
