# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/datastore_response/search_response"

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
      class RelationJoin < ::Data.define(:field, :document_id_field_name, :filter_id_field_name, :id_cardinality, :doc_cardinality, :additional_filter, :foreign_key_nested_paths)
        def self.from(field)
          return nil if (relation = field.relation).nil?

          doc_cardinality = field.type.collection? ? Cardinality::Many : Cardinality::One

          if relation.direction == :in
            # An inbound foreign key has some field (such as `foo_id`) on another document that points
            # back to the `id` field on the document with the relation.
            #
            # The cardinality of the document id field on an inbound relation is always 1 since
            # it is always the primary key `id` field.
            new(field, "id", relation.foreign_key, Cardinality::One, doc_cardinality, relation.additional_filter, relation.foreign_key_nested_paths)
          else
            # An outbound foreign key has some field (such as `foo_id`) on the document with the relation
            # that point out to the `id` field of another document.
            new(field, relation.foreign_key, "id", doc_cardinality, doc_cardinality, relation.additional_filter, relation.foreign_key_nested_paths)
          end
        end

        def blank_value
          doc_cardinality.blank_value
        end

        # Extracts a single id or a list of ids from the given document, as required by the relation.
        def extract_id_or_ids_from(document, log_warning)
          id_or_ids = document.fetch(document_id_field_name) do
            log_warning.call(document: document, problem: "#{document_id_field_name} is missing from the document")
            blank_value
          end

          normalize_ids(id_or_ids) do |problem|
            log_warning.call(document: document, problem: "#{document_id_field_name}: #{problem}")
          end
        end

        # Normalizes the given documents, ensuring it has the expected cardinality.
        def normalize_documents(response, &handle_warning)
          doc_cardinality.normalize(response, handle_warning: handle_warning, &:id)
        end

        private

        def normalize_ids(id_or_ids, &handle_warning)
          id_cardinality.normalize(id_or_ids, handle_warning: handle_warning, &:itself)
        end

        module Cardinality
          module Many
            def self.normalize(list_or_scalar, handle_warning:)
              return list_or_scalar if list_or_scalar.is_a?(Enumerable)
              handle_warning.call("scalar instead of a list")
              Array(list_or_scalar)
            end

            def self.blank_value
              DatastoreResponse::SearchResponse::EMPTY
            end
          end

          module One
            def self.normalize(list_or_scalar, handle_warning:, &deterministic_comparator)
              return list_or_scalar unless list_or_scalar.is_a?(Enumerable)
              handle_warning.call("list of more than one item instead of a scalar") if list_or_scalar.size > 1
              list_or_scalar.min_by(&deterministic_comparator)
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
