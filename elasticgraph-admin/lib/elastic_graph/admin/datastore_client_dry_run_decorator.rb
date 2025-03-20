# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "forwardable"

module ElasticGraph
  class Admin
    # Decorator that wraps a datastore client in order to implement dry run behavior.
    # All write operations are implemented as no-ops, while read operations are passed through
    # to the wrapped datastore client.
    #
    # We prefer this over having to check a `dry_run` flag in many places because that's
    # easy to forget. One mistake and a dry run isn't truly a dry run!
    #
    # In contrast, this gives us a strong guarantee that dry run mode truly avoids mutating
    # any datastore state. This decorator specifically picks and chooses which operations it
    # allows.
    #
    # - Read operations are forwarded to the wrapped datastore client.
    # - Write operations are implemented as no-ops.
    #
    # If/when the calling code evolves to call a new method on this, it'll trigger
    # `NoMethodError`, giving us a good chance to evaluate how this decorator should
    # support a particular API. This is also why this doesn't use Ruby's `delegate` library,
    # because we don't want methods automatically delegated; we want to opt-in to only the read-only methods.
    class DatastoreClientDryRunDecorator
      extend Forwardable

      def initialize(wrapped_client)
        @wrapped_client = wrapped_client
      end

      # Cluster APIs
      def_delegators :@wrapped_client, :get_flat_cluster_settings, :get_cluster_health

      def put_persistent_cluster_settings(*) = nil

      # Script APIs
      def_delegators :@wrapped_client, :get_script

      def put_script(*) = nil

      def delete_script(*) = nil

      # Index Template APIs
      def_delegators :@wrapped_client, :get_index_template

      def delete_index_template(*) = nil

      def put_index_template(*) = nil

      # Index APIs
      def_delegators :@wrapped_client, :get_index, :list_indices_matching

      def delete_indices(*) = nil

      def create_index(*) = nil

      def put_index_mapping(*) = nil

      def put_index_settings(*) = nil

      # Document APIs
      def_delegators :@wrapped_client, :get, :search, :msearch

      def delete_all_documents(*) = nil

      def bulk(*) = nil
    end
  end
end
