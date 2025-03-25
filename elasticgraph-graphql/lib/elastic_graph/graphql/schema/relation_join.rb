# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/datastore_response/search_response"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    class Schema
      # Represents the join between documents for a relation.
      #
      # Note that this class assumes a valid, well-formed schema definition, and makes no
      # attempt to provide user-friendly errors when that is not the case. For example,
      # we assume that a nested relationship field has at most one relationship directive.
      # The (as yet unwritten) schema linter should validate such things eventually.
      # When we do encounter errors at runtime (such as getting a scalar where we expect
      # a list, or vice-versa), this class attempts to deal with as best as it can (sometimes
      # simply picking one record or id from many!) and logs a warning.
      #
      # Note: this class isn't driven directly by tests. It exist purely to serve the needs
      # of ElasticGraph::Resolvers::NestedRelationships, and is driven by that class's tests.
      # It lives here because it's useful to expose it off of a `Field` since it's a property
      # of the field and that lets us memoize it on the field itself.
      class RelationJoin < ::Data.define(:field, :document_id_field_path, :filter_id_field_path, :id_cardinality, :doc_cardinality, :additional_filter, :foreign_key_nested_paths)
        def self.from(field)
          return nil if (relation = field.relation).nil?

          doc_cardinality = field.type.collection? ? Cardinality::Many : Cardinality::One
          foreign_key_nested_paths = relation.foreign_key_nested_paths.map { |p| p.split(".") }
          foreign_key_path = relation.foreign_key.split(".")

          if relation.direction == :in
            # An inbound foreign key has some field (such as `foo_id`) on another document that points
            # back to the `id` field on the document with the relation.
            #
            # The cardinality of the document id field on an inbound relation is always 1 since
            # it is always the primary key `id` field.
            new(field, ["id"], foreign_key_path, Cardinality::One, doc_cardinality, relation.additional_filter, foreign_key_nested_paths)
          else
            # An outbound foreign key has some field (such as `foo_id`) on the document with the relation
            # that point out to the `id` field of another document.
            new(field, foreign_key_path, ["id"], doc_cardinality, doc_cardinality, relation.additional_filter, foreign_key_nested_paths)
          end
        end

        def blank_value
          doc_cardinality.blank_value
        end

        # Extracts a single id or a list of ids from the given document, as required by the relation.
        def extract_id_or_ids_from(document, log_warning)
          id_or_ids = Support::HashUtil.fetch_value_at_path(document, document_id_field_path) do
            log_warning.call(document: document, problem: "#{document_id_field_path.join(".")} is missing from the document")
            blank_value
          end

          normalize_ids(id_or_ids) do |problem|
            log_warning.call(document: document, problem: "#{document_id_field_path.join(".")}: #{problem}")
          end
        end

        # Normalizes the given documents, ensuring it has the expected cardinality.
        def normalize_documents(response, &handle_warning)
          doc_cardinality.normalize(response, handle_warning: handle_warning) { |doc| (_ = doc).id }
        end

        private

        def normalize_ids(id_or_ids, &handle_warning)
          id_cardinality.normalize(id_or_ids, handle_warning: handle_warning) { |id| id }
        end

        module Cardinality
          module Many
            def self.normalize(list_or_scalar, handle_warning:)
              case list_or_scalar
              when ::Enumerable
                list_or_scalar
              else
                handle_warning.call("scalar instead of a list")
                Array(list_or_scalar)
              end
            end

            def self.blank_value
              DatastoreResponse::SearchResponse::EMPTY
            end
          end

          module One
            def self.normalize(list_or_scalar, handle_warning:, &deterministic_comparator)
              case list_or_scalar
              when ::Enumerable
                handle_warning.call("list of more than one item instead of a scalar") if (_ = list_or_scalar).size > 1
                list_or_scalar.min_by(&deterministic_comparator)
              else
                list_or_scalar
              end
            end

            def self.blank_value
              nil
            end
          end
        end
      end
    end
  end
end
