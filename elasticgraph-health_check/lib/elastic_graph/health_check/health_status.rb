# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/health_check/constants"

module ElasticGraph
  module HealthCheck
    # Encapsulates all of the status information for an ElasticGraph GraphQL endpoint.
    # Computes a `category` for the status of the ElasticGraph endpoint.
    #
    #   - unhealthy: the endpoint should not be used
    #   - degraded: the endpoint can be used, but prefer a healthy endpoint over it
    #   - healthy: the endpoint should be used
    class HealthStatus < ::Data.define(:cluster_health_by_name, :latest_record_by_type, :category)
      def initialize(cluster_health_by_name:, latest_record_by_type:)
        super(
          cluster_health_by_name: cluster_health_by_name,
          latest_record_by_type: latest_record_by_type,
          category: compute_category(cluster_health_by_name, latest_record_by_type)
        )
      end

      def to_loggable_description
        latest_record_descriptions = latest_record_by_type
          .sort_by(&:first) # sort by type name
          .map { |type, record| record&.to_loggable_description(type) || "Latest #{type} (missing)" }
          .map { |description| "- #{description}" }

        cluster_health_descriptions = cluster_health_by_name
          .sort_by(&:first) # sort by cluster name
          .map { |name, health| "\n- #{health.to_loggable_description(name)}" }

        <<~EOS.strip.gsub("\n\n\n", "\n")
          HealthStatus: #{category} (checked #{cluster_health_by_name.size} clusters, #{latest_record_by_type.size} latest records)
          #{latest_record_descriptions.join("\n")}
          #{cluster_health_descriptions.join("\n")}
        EOS
      end

      private

      def compute_category(cluster_health_by_name, latest_record_by_type)
        cluster_statuses = cluster_health_by_name.values.map(&:status)
        return :unhealthy if cluster_statuses.include?("red")

        return :degraded if cluster_statuses.include?("yellow")
        return :degraded if latest_record_by_type.values.any? { |v| v.nil? || v.too_old? }

        :healthy
      end

      # Encapsulates the status information for a single datastore cluster.
      ClusterHealth = ::Data.define(*DATASTORE_CLUSTER_HEALTH_FIELDS.to_a) do
        # @implements ClusterHealth

        def to_loggable_description(name)
          field_values = to_h.map { |field, value| "  #{field}: #{value.inspect}" }
          "#{name} cluster health (#{status}):\n#{field_values.join("\n")}"
        end
      end

      # Encapsulates information about the latest record of a type.
      LatestRecord = ::Data.define(
        :id, # the id of the record
        :timestamp, # the record's timestamp
        :seconds_newer_than_required # the recency of the record relative to expectation; positive == more recent
      ) do
        # @implements LatestRecord
        def to_loggable_description(type)
          rounded_age = seconds_newer_than_required.round(2).abs

          if too_old?
            "Latest #{type} (too old): #{id} / #{timestamp.iso8601} (#{rounded_age}s too old)"
          else
            "Latest #{type} (recent enough): #{id} / #{timestamp.iso8601} (#{rounded_age}s newer than required)"
          end
        end

        def too_old?
          seconds_newer_than_required < 0
        end
      end
    end
  end
end
