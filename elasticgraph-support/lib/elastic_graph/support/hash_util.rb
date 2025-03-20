# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # @private
    class HashUtil
      # Fetches a key from a hash (just like `Hash#fetch`) but with a more verbose error message when the key is not found.
      # The error message indicates the available keys unlike `Hash#fetch`.
      def self.verbose_fetch(hash, key)
        hash.fetch(key) do
          raise ::KeyError, "key not found: #{key.inspect}. Available keys: #{hash.keys.inspect}."
        end
      end

      # Like `Hash#to_h`, but strict. When the given input has conflicting keys, `Hash#to_h` will happily let
      # the last pair when. This method instead raises an exception.
      def self.strict_to_h(pairs)
        hash = pairs.to_h

        if hash.size < pairs.size
          conflicting_keys = pairs.map(&:first).tally.filter_map { |key, count| key if count > 1 }
          raise ::KeyError, "Cannot build a strict hash, since input has conflicting keys: #{conflicting_keys.inspect}."
        end

        hash
      end

      # Like `Hash#merge`, but verifies that the hashes were strictly disjoint (e.g. had no keys in common).
      # An error is raised if they do have any keys in common.
      def self.disjoint_merge(hash1, hash2)
        conflicting_keys = [] # : ::Array[untyped]
        merged = hash1.merge(hash2) do |key, v1, _v2|
          conflicting_keys << key
          v1
        end

        unless conflicting_keys.empty?
          raise ::KeyError, "Hashes were not disjoint. Conflicting keys: #{conflicting_keys.inspect}."
        end

        merged
      end

      # Recursively transforms any hash keys in the given object to string keys, without
      # mutating the provided argument.
      def self.stringify_keys(object)
        transform_keys(object, :to_s)
      end

      # Recursively transforms any hash keys in the given object to symbol keys, without
      # mutating the provided argument.
      #
      # Important note: this should never be used on untrusted input. Symbols are not GCd in
      # Ruby in the same way as strings.
      def self.symbolize_keys(object)
        transform_keys(object, :to_sym)
      end

      # Recursively prunes nil values from the hash, at any level of its structure, without
      # mutating the provided argument. Key paths that are pruned are yielded to the caller
      # to allow the caller to have awareness of what was pruned.
      def self.recursively_prune_nils_from(object, &block)
        recursively_prune_if(object, block, &:nil?)
      end

      # Recursively prunes nil values or empty hash/array values from the hash, at any level
      # of its structure, without mutating the provided argument. Key paths that are pruned
      # are yielded to the caller to allow the caller to have awareness of what was pruned.
      def self.recursively_prune_nils_and_empties_from(object, &block)
        recursively_prune_if(object, block) do |value|
          if value.is_a?(::Hash) || value.is_a?(::Array)
            value.empty?
          else
            value.nil?
          end
        end
      end

      # Recursively flattens the provided source hash, converting keys to strings along the way
      # with dots used to separate nested parts. For example:
      #
      # flatten_and_stringify_keys({ a: { b: 3 }, c: 5 }, prefix: "foo") returns:
      # { "foo.a.b" => 3, "foo.c" => 5 }
      def self.flatten_and_stringify_keys(source_hash, prefix: nil)
        # @type var flat_hash: ::Hash[::String, untyped]
        flat_hash = {}
        prefix = prefix ? "#{prefix}." : ""
        # `_ =` is needed by steep because it thinks `prefix` could be `nil` in spite of the above line.
        populate_flat_hash(source_hash, _ = prefix, flat_hash)
        flat_hash
      end

      # Recursively merges the values from `hash2` into `hash1`, without mutating either `hash1` or `hash2`.
      # When a key is in both `hash2` and `hash1`, takes the value from `hash2` just like `Hash#merge` does.
      def self.deep_merge(hash1, hash2)
        # `_ =` needed to satisfy steep--the types here are quite complicated.
        _ = hash1.merge(hash2) do |key, hash1_value, hash2_value|
          if ::Hash === hash1_value && ::Hash === hash2_value
            deep_merge(hash1_value, hash2_value)
          else
            hash2_value
          end
        end
      end

      # Fetches a list of (potentially) nested value from a hash. The `key_path` is expected
      # to be a string with dots between the nesting levels (e.g. `foo.bar`). Returns `[]` if
      # the value at any parent key is `nil`. Returns a flat array of values if the structure
      # at any level is an array.
      #
      # Raises an error if the key is not found unless a default block is provided.
      # Raises an error if any parent value is not a hash as expected.
      # Raises an error if the provided path is not a full path to a leaf in the nested structure.
      def self.fetch_leaf_values_at_path(hash, key_path, &default)
        do_fetch_leaf_values_at_path(hash, key_path.split("."), 0, &default)
      end

      # Fetches a single value from the hash at the given path. The `key_path` is expected
      # to be a string with dots between the nesting levels (e.g. `foo.bar`).
      #
      # If any parent value is not a hash as expected, raises an error.
      # If the key at any level is not found, yields to the provided block (which can provide a default value)
      # or raises an error if no block is provided.
      def self.fetch_value_at_path(hash, key_path)
        path_parts = key_path.split(".")

        path_parts.each.with_index(1).reduce(hash) do |inner_hash, (key, num_parts)|
          if inner_hash.is_a?(::Hash)
            inner_hash.fetch(key) do
              missing_path = path_parts.first(num_parts).join(".")
              return yield missing_path if block_given?
              raise KeyError, "Key not found: #{missing_path.inspect}"
            end
          else
            raise KeyError, "Value at key #{path_parts.first(num_parts - 1).join(".").inspect} is not a `Hash` as expected; " \
              "instead, was a `#{(_ = inner_hash).class}`"
          end
        end
      end

      # Note: this implementation was chosen based off of a benchmark in
      # `benchmarks/hash_util/key_transformations.rb`.
      private_class_method def self.transform_keys(object, method)
        case object
        when ::Hash
          result = {} # : ::Hash[untyped, untyped]
          object.each do |key, value|
            result[key.send(method)] = transform_keys(value, method)
          end
          result
        when ::Array
          object.map { |item| transform_keys(item, method) }
        else
          object
        end
      end

      private_class_method def self.recursively_prune_if(object, notify_pruned_path)
        recursively_transform(object) do |key, value, hash, key_path|
          if yield(value)
            notify_pruned_path&.call(key_path)
          else
            hash[key] = value
          end
        end
      end

      private_class_method def self.recursively_transform(object, key_path = nil, &hash_entry_handler)
        case object
        when ::Hash
          # @type var initial: ::Hash[key, value]
          initial = {}
          object.each_with_object(initial) do |(key, value), hash|
            updated_path = key_path ? "#{key_path}.#{key}" : key.to_s
            value = recursively_transform(value, updated_path, &hash_entry_handler)
            hash_entry_handler.call(key, value, hash, updated_path)
          end
        when ::Array
          object.map.with_index do |item, index|
            recursively_transform(item, "#{key_path}[#{index}]", &hash_entry_handler)
          end
        else
          object
        end
      end

      private_class_method def self.populate_flat_hash(source_hash, prefix, flat_hash)
        source_hash.each do |key, value|
          if value.is_a?(::Hash)
            populate_flat_hash(value, "#{prefix}#{key}.", flat_hash)
          elsif value.is_a?(::Array) && value.grep(::Hash).any?
            raise ArgumentError, "`flatten_and_stringify_keys` cannot handle nested arrays of hashes, but got: #{value.inspect}"
          else
            flat_hash["#{prefix}#{key}"] = value
          end
        end
      end

      private_class_method def self.do_fetch_leaf_values_at_path(object, path_parts, level_index, &default)
        if level_index == path_parts.size
          if object.is_a?(::Hash)
            raise KeyError, "Key was not a path to a leaf field: #{path_parts.join(".").inspect}"
          else
            return Array(object)
          end
        end

        case object
        when nil
          []
        when ::Hash
          key = path_parts[level_index]
          if object.key?(key)
            do_fetch_leaf_values_at_path(object.fetch(key), path_parts, level_index + 1, &default)
          else
            missing_path = path_parts.first(level_index + 1).join(".")
            if default
              Array(default.call(missing_path))
            else
              raise KeyError, "Key not found: #{missing_path.inspect}"
            end
          end
        when ::Array
          object.flat_map do |element|
            do_fetch_leaf_values_at_path(element, path_parts, level_index, &default)
          end
        else
          # Note: we intentionally do not put the value (`current_level_hash`) in the
          # error message, as that would risk leaking PII. But the class of the value should be OK.
          raise KeyError, "Value at key #{path_parts.first(level_index).join(".").inspect} is not a `Hash` as expected; " \
            "instead, was a `#{object.class}`"
        end
      end
    end
  end
end
