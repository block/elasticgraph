# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  class Indexer
    module Operation
      # Responsible for maintaining state and accumulating list counts while we traverse the `data` we are preparing
      # to update in the index. Much of the complexity here is due to the fact that we have 3 kinds of list fields:
      # scalar lists, embedded object lists, and `nested` object lists.
      #
      # The Elasticsearch/OpenSearch `nested` type[^1] indexes objects of this type as separate hidden documents. As a result,
      # each `nested` object type gets its own `__counts` field. In contrast, embedded object lists get flattened into separate
      # entries (one per field path) in a flat map (with `dot_separated_path: values_at_path` entries) at the document root.
      #
      # We mirror this structure with our `__counts`: each document (either a root document, or a hidden `nested` document)
      # gets its own `__counts` field, so we essentially have multiple "count parents". Each `__counts` field is a map,
      # keyed by field paths, and containing the number of list elements at that field path after the flattening has
      # occurred.
      #
      # The index mapping defines where the `__counts` fields go. This abstraction uses the mapping to determine when
      # it needs to create a new "count parent".
      #
      # Note: instances of this class are "shallow immutable" (none of the attributes of an instance can be reassigned)
      # but the `counts` attribute is itself a mutable hash--we use it to accumulate the list counts as we traverse the
      # structure.
      #
      # [^1]: https://www.elastic.co/guide/en/elasticsearch/reference/8.9/nested.html
      CountAccumulator = ::Data.define(
        # Hash containing the counts we have accumulated so far. This hash gets mutated as we accumulate,
        # and multiple accumulator instances share the same hash instance. However, a new `counts` hash will
        # be created when we reach a new parent.
        :counts,
        # String describing our current location in the traversed structure relative to the current parent.
        # This gets replaced on new accumulator instances as we traverse the data structure.
        :path_from_parent,
        # String describing our current location in the traversed structure relative to the overall document root.
        # This gets replaced on new accumulator instances as we traverse the data structure.
        :path_from_root,
        # The index mapping at the current level of the structure when this accumulator instance was created.
        # As we traverse new levels of the data structure, new `CountAccumulator` instances will be created with
        # the `mapping` updated to reflect the new level of the structure we are at.
        :mapping,
        # Set of field paths to subfields of `LIST_COUNTS_FIELD` for the current source relationship.
        # This will be used to determine which subfields of the `LIST_COUNTS_FIELD` are populated.
        :list_counts_field_paths_for_source,
        # Indicates if our current path is underneath a list; if so, `maybe_increment` will increment when called.
        :has_list_ancestor
      ) do
        # @implements CountAccumulator
        def self.merge_list_counts_into(params, mapping:, list_counts_field_paths_for_source:)
          # Here we compute the counts of our list elements so that we can index it.
          data = compute_list_counts_of(params.fetch("data"), CountAccumulator.new_parent(
            # We merge in `type: nested` since the `nested` type indicates a new count accumulator parent and we want that applied at the root.
            mapping.merge("type" => "nested"),
            list_counts_field_paths_for_source
          ))

          # The root `__counts` field needs special handling due to our `sourced_from` feature. Anything in `data`
          # will overwrite what's in the specified fields when the script executes, but since there could be list
          # fields from multiple sources, we need `__counts` to get merged properly. So here we "promote" it from
          # `data.__counts` to being a root-level parameter.
          params.merge(
            "data" => data.except(LIST_COUNTS_FIELD),
            LIST_COUNTS_FIELD => data[LIST_COUNTS_FIELD]
          )
        end

        def self.compute_list_counts_of(value, parent_accumulator)
          case value
          when nil
            value
          when ::Hash
            parent_accumulator.maybe_increment
            parent_accumulator.process_hash(value) do |key, subvalue, accumulator|
              [key, compute_list_counts_of(subvalue, accumulator[key])]
            end
          when ::Array
            parent_accumulator.process_list(value) do |element, accumulator|
              compute_list_counts_of(element, accumulator)
            end
          else
            parent_accumulator.maybe_increment
            value
          end
        end

        # Creates an initially empty accumulator instance for a new parent (either at the overall document
        # root are at the root of a `nested` object).
        def self.new_parent(mapping, list_counts_field_paths_for_source, path_from_root: nil)
          count_field_prefix = path_from_root ? "#{path_from_root}.#{LIST_COUNTS_FIELD}." : "#{LIST_COUNTS_FIELD}."

          initial_counts = (mapping.dig("properties", LIST_COUNTS_FIELD, "properties") || {}).filter_map do |field, _|
            [field, 0] if list_counts_field_paths_for_source.include?(count_field_prefix + field)
          end.to_h

          new(initial_counts, nil, path_from_root, mapping, list_counts_field_paths_for_source, false)
        end

        # Processes the given hash, beginning a new parent if need. A new parent is needed if the
        # current mapping has a `__counts` field.
        #
        # Yields repeatedly (once per hash entry). We yield the entry key/value, and an accumulator
        # instance (either the current `self` or a new parent).
        #
        # Afterwards, merges the resulting `__counts` into the hash before it's returned, as needed.
        def process_hash(hash)
          mapping_type = mapping["type"]

          # As we traverse through the JSON object structure, we also have to traverse through the
          # condenseed mapping. Doing this requires that the `properties` of the index mapping
          # match the fields of the JSON data structure. However, Elasticsearch/OpenSearch have a number of field
          # types which can be represented as a JSON object in an indexing call, but which have no
          # `properties` in the mapping. We can't successfully traverse through the JSON data and the
          # mapping when we encounter these field types (since the mapping has no record of the
          # subfields) so we must treat these types as a special case; we can't proceed, and we won't
          # have any lists to count, anyway.
          return hash if DATASTORE_PROPERTYLESS_OBJECT_TYPES.include?(mapping_type)

          # THe `nested` type indicates a new document level, so if it's not `nested`, we should process the hash without making a new parent.
          return hash.to_h { |key, value| yield key, value, self } unless mapping_type == "nested"

          # ...but otherwise, we should make a new parent.
          new_parent = CountAccumulator.new_parent(mapping, list_counts_field_paths_for_source, path_from_root: path_from_root)
          updated_hash = hash.to_h { |key, value| yield key, value, new_parent }

          # If we have a LIST_COUNTS_FIELD at this level of our mapping, we should merge in the counts hash from the new parent.
          if mapping.dig("properties", LIST_COUNTS_FIELD)
            updated_hash.merge(LIST_COUNTS_FIELD => new_parent.counts)
          else
            updated_hash
          end
        end

        # Processes the given list, tracking the fact that subpaths have a list ancestor.
        def process_list(list)
          child_accumulator = with(has_list_ancestor: true)
          list.map { |value| yield value, child_accumulator }
        end

        # Increments the count at the current `path_from_parent` in the current parent's counts hash if we are under a list.
        def maybe_increment
          return unless has_list_ancestor

          key = path_from_parent.to_s
          counts[key] = counts.fetch(key) + 1
        end

        # Creates a "child" accumulator at the given subpath. Should be used as we traverse the data structure.
        def [](subpath)
          with(
            path_from_parent: path_from_parent ? "#{path_from_parent}#{LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR}#{subpath}" : subpath,
            path_from_root: path_from_root ? "#{path_from_root}.#{subpath}" : subpath,
            mapping: mapping.fetch("properties").fetch(subpath)
          )
        end
      end
    end
  end
end
