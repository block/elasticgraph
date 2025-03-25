# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/hash_util"

module ElasticGraph
  module Support
    RSpec.describe HashUtil do
      describe ".verbose_fetch" do
        it "returns the value for the provided key" do
          hash = {foo: 1}

          expect(HashUtil.verbose_fetch(hash, :foo)).to eq 1

          # ...just like Hash#fetch
          expect(hash.fetch(:foo)).to eq 1
        end

        it "indicates the available keys in the error message when given a missing key" do
          hash = {foo: 1, bar: 2}

          expect {
            HashUtil.verbose_fetch(hash, :bazz)
          }.to raise_error KeyError, "key not found: :bazz. Available keys: [:foo, :bar]."

          # ...in contrast to Hash#fetch which does not include the available keys
          expect {
            hash.fetch(:bazz)
          }.to raise_error KeyError, "key not found: :bazz"
        end
      end

      describe ".strict_to_h" do
        it "builds a hash from a list of key/value pairs" do
          pairs = [[:foo, 1], [:bar, 2]]

          expect(HashUtil.strict_to_h(pairs)).to eq({foo: 1, bar: 2})

          # ...just like Hash#to_h
          expect(pairs.to_h).to eq({foo: 1, bar: 2})
        end

        it "raises an error if there are conflicting keys, unlike `Hash#to_h`" do
          pairs = [[:foo, 1], [:bar, 2], [:foo, 3], [:bazz, 4], [:bar, 1]]

          expect {
            HashUtil.strict_to_h(pairs)
          }.to raise_error KeyError, "Cannot build a strict hash, since input has conflicting keys: [:foo, :bar]."

          # ... in contrast to Hash#to_h, which allows later entries to stomp earlier ones
          expect(pairs.to_h).to eq({foo: 3, bazz: 4, bar: 1})
        end
      end

      describe ".disjoint_merge" do
        it "merges two disjoint hashes" do
          hash1 = {foo: 1, bar: 2}
          hash2 = {bazz: 3}

          expect(HashUtil.disjoint_merge(hash1, hash2)).to eq({foo: 1, bar: 2, bazz: 3})

          # ...just like Hash#merge
          expect(hash1.merge(hash2)).to eq({foo: 1, bar: 2, bazz: 3})
        end

        it "raises an error if the hashes are not disjoint" do
          hash1 = {foo: 1, bar: 2}
          hash2 = {foo: 3}

          expect {
            HashUtil.disjoint_merge(hash1, hash2)
          }.to raise_error KeyError, "Hashes were not disjoint. Conflicting keys: [:foo]."

          # ...in contrast to Hash#merge, which lets the entry from the last hash win.
          expect(hash1.merge(hash2)).to eq({foo: 3, bar: 2})
        end
      end

      describe ".stringify_keys" do
        it "leaves a hash with string keys unchanged" do
          expect(HashUtil.stringify_keys({"a" => 1})).to eq({"a" => 1})
        end

        it "replaces symbol keys with string keys" do
          expect(HashUtil.stringify_keys({a: 1, b: 2})).to eq({"a" => 1, "b" => 2})
        end

        it "recursively stringifies keys through a deeply nested hash" do
          expect(HashUtil.stringify_keys({a: {b: {c: 2}}})).to eq({"a" => {"b" => {"c" => 2}}})
        end

        it "recursively stringifies keys through nested arrays" do
          expect(HashUtil.stringify_keys({a: [{b: 1}, {c: 2}]})).to eq({"a" => [{"b" => 1}, {"c" => 2}]})
        end
      end

      describe ".symbolize_keys" do
        it "leaves a hash with symbol keys unchanged" do
          expect(HashUtil.symbolize_keys({a: 1})).to eq({a: 1})
        end

        it "replaces string keys with symbol keys" do
          expect(HashUtil.symbolize_keys({"a" => 1, "b" => 2})).to eq({a: 1, b: 2})
        end

        it "recursively symbolizes keys through a deeply nested hash" do
          expect(HashUtil.symbolize_keys({"a" => {"b" => {"c" => 2}}})).to eq({a: {b: {c: 2}}})
        end

        it "recursively symbolizes keys through nested arrays" do
          expect(HashUtil.symbolize_keys({"a" => [{"b" => 1}, {"c" => 2}]})).to eq({a: [{b: 1}, {c: 2}]})
        end
      end

      describe ".recursively_prune_nils_from" do
        it "echoes a hash back that has no nils in it" do
          result = HashUtil.recursively_prune_nils_from({a: 1, b: {c: 2, d: [1, 2]}})
          expect(result).to eq({a: 1, b: {c: 2, d: [1, 2]}})
        end

        it "removes entries with `nil` values at any level of a nested hash structure" do
          result = HashUtil.recursively_prune_nils_from({a: 1, b: {c: 2, d: [1, 2], e: nil}, f: nil})
          expect(result).to eq({a: 1, b: {c: 2, d: [1, 2]}})
        end

        it "recursively applies to hashes inside nested arrays" do
          result = HashUtil.recursively_prune_nils_from({a: 1, b: {c: 2, d: [{g: nil, h: 1}, {g: 2, h: nil}]}})
          expect(result).to eq({a: 1, b: {c: 2, d: [{h: 1}, {g: 2}]}})
        end

        it "yields each pruned key path to support so the caller can do things like log warnings" do
          expect { |probe|
            HashUtil.recursively_prune_nils_from({
              z: nil,
              a: 1,
              b: {
                c: 2,
                d: [
                  {g: nil, h: 1},
                  {g: 2, h: nil}
                ],
                foo: nil
              },
              bar: nil
            }, &probe)
          }.to yield_successive_args(
            "z",
            "b.d[0].g",
            "b.d[1].h",
            "b.foo",
            "bar"
          )
        end
      end

      describe ".recursively_prune_nils_and_empties_from" do
        it "echoes a hash back that has no nils or empties in it" do
          result = HashUtil.recursively_prune_nils_and_empties_from({a: 1, b: {c: 2, d: [1, 2]}})
          expect(result).to eq({a: 1, b: {c: 2, d: [1, 2]}})
        end

        it "removes entries with `nil` values at any level of a nested hash structure" do
          result = HashUtil.recursively_prune_nils_and_empties_from({a: 1, b: {c: 2, d: [1, 2], e: nil}, f: nil})
          expect(result).to eq({a: 1, b: {c: 2, d: [1, 2]}})
        end

        it "removes empty hash or array entries at any level of a nested hash structure" do
          result = HashUtil.recursively_prune_nils_and_empties_from({a: 1, b: {c: 2, d: [1, 2], e: []}, f: {}})
          expect(result).to eq({a: 1, b: {c: 2, d: [1, 2]}})
        end

        it "does not remove empty strings" do
          result = HashUtil.recursively_prune_nils_and_empties_from({a: ""})
          expect(result).to eq({a: ""})
        end

        it "recursively applies nil pruning to hashes inside nested arrays" do
          result = HashUtil.recursively_prune_nils_and_empties_from({a: 1, b: {c: 2, d: [{g: nil, h: 1}, {g: 2, h: nil}]}})
          expect(result).to eq({a: 1, b: {c: 2, d: [{h: 1}, {g: 2}]}})
        end

        it "recursively applies empty object pruning to hashes inside nested arrays" do
          result = HashUtil.recursively_prune_nils_and_empties_from({a: 1, b: {c: 2, d: [{g: [], h: 1}, {g: 2, h: {}}]}})
          expect(result).to eq({a: 1, b: {c: 2, d: [{h: 1}, {g: 2}]}})
        end

        it "yields each pruned key path to support so the caller can do things like log warnings" do
          expect { |probe|
            HashUtil.recursively_prune_nils_and_empties_from({
              z: nil,
              a: 1,
              b: {
                c: 2,
                d: [
                  {g: nil, h: 1},
                  {g: 2, h: {}}
                ],
                foo: []
              },
              bar: nil
            }, &probe)
          }.to yield_successive_args(
            "z",
            "b.d[0].g",
            "b.d[1].h",
            "b.foo",
            "bar"
          )
        end
      end

      describe ".flatten_and_stringify_keys" do
        it "leaves a flat hash with string keys unchanged" do
          expect(HashUtil.flatten_and_stringify_keys({"a" => 1, "b.c" => 2})).to eq({"a" => 1, "b.c" => 2})
        end

        it "converts symbol keys to strings" do
          expect(HashUtil.flatten_and_stringify_keys({:a => 1, "b.c" => 2})).to eq({"a" => 1, "b.c" => 2})
        end

        it "flattens nested hashes using dot-separated keys" do
          expect(HashUtil.flatten_and_stringify_keys({a: {:b => 3, 2 => false, :c => {d: 5}}, h: 9})).to eq(
            {"a.b" => 3, "a.2" => false, "a.c.d" => 5, "h" => 9}
          )
        end

        it "supports a `prefix` arg" do
          expect(HashUtil.flatten_and_stringify_keys({a: {:b => 3, 2 => false, :c => {d: 5}}, h: 9}, prefix: "foo")).to eq(
            {"foo.a.b" => 3, "foo.a.2" => false, "foo.a.c.d" => 5, "foo.h" => 9}
          )
        end

        it "raises an exception on an array of hashes" do
          expect {
            HashUtil.flatten_and_stringify_keys({a: [{b: 1}, {b: 2}]})
          }.to raise_error(/cannot handle nested arrays of hashes/)
        end

        it "leaves an array of scalars or an empty array unchanged" do
          expect(HashUtil.flatten_and_stringify_keys({a: {b: [1, 2], c: ["d", "f"], g: []}})).to eq(
            {"a.b" => [1, 2], "a.c" => ["d", "f"], "a.g" => []}
          )
        end
      end

      describe ".deep_merge" do
        it "is a no-op when merging an empty hash into an existing hash" do
          hash1 = {
            property1: 1,
            property2: {
              property3: "abc"
            }
          }
          expect(HashUtil.deep_merge(hash1, {})).to eq(hash1)
        end

        it "returns a deep copy of hash2 when hash1 is empty" do
          hash2 = {
            property1: 1,
            property2: {
              property3: "abc"
            }
          }
          expect(HashUtil.deep_merge({}, hash2)).to eq(hash2)
        end

        it "values from hash2 overwrite values from hash1 (just like HashUtil#merge) when both are flat hashes with same keys" do
          hash1 = {
            property1: 1,
            property2: 2
          }

          hash2 = {
            property1: 3,
            property2: 4
          }
          expect(HashUtil.deep_merge(hash1, hash2)).to eq(hash2)
        end

        it "values from hash2 overwrite values from hash1 for common keys and copies their unique keys when hash1 and hash2 have different keys" do
          hash1 = {
            property1: 1,
            property2: 2,
            property3: 3
          }

          hash2 = {
            property1: 3,
            property5: 5
          }
          expect(HashUtil.deep_merge(hash1, hash2)).to eq({
            property1: 3,
            property2: 2,
            property3: 3,
            property5: 5
          })
        end

        it "merge values between nested hashes with different keys" do
          hash1 = {
            property1: {
              property2: {
                property3: 2,
                property4: {
                  property5: nil
                },
                property100: 90
              }
            }
          }

          hash2 = {
            property1: {
              property2: {
                property3: 5,
                property4: {
                  property5: 7,
                  property6: {
                    property7: 10
                  }
                }
              },
              property3: {
                property4: {
                  property5: 6
                }
              }
            },
            property5: 5
          }
          expect(HashUtil.deep_merge(hash1, hash2)).to eq({
            property1: {
              property2: {
                property3: 5,
                property4: {
                  property5: 7,
                  property6: {
                    property7: 10
                  }
                },
                property100: 90
              },
              property3: {
                property4: {
                  property5: 6
                }
              }
            },
            property5: 5
          })
        end
      end

      describe ".fetch_value_at_path" do
        it "returns the single value at the given path" do
          hash = {
            "other" => 1,
            "foo.bar.bazz" => "should not be returned",
            "foo" => {
              "other" => 2,
              "bar" => {
                "bazz" => 12,
                "other" => 3,
                "goo" => nil
              }
            }
          }

          expect(HashUtil.fetch_value_at_path(hash, ["other"])).to eq 1
          expect(HashUtil.fetch_value_at_path(hash, ["foo", "other"])).to eq 2
          expect(HashUtil.fetch_value_at_path(hash, ["foo", "bar", "bazz"])).to eq 12
          expect(HashUtil.fetch_value_at_path(hash, ["foo", "bar", "other"])).to eq 3
          expect(HashUtil.fetch_value_at_path(hash, ["foo", "bar", "goo"])).to eq nil
        end

        it "returns an array of values if that's what's at the given path" do
          hash = {
            "other" => 1,
            "foo.bar.bazz" => "should not be returned",
            "foo" => {
              "other" => 2,
              "bar" => {
                "bazz" => [12, 3],
                "other" => 3
              }
            }
          }

          expect(HashUtil.fetch_value_at_path(hash, ["foo", "bar", "bazz"])).to eq [12, 3]
        end

        it "returns a hash of data if that's what's at the given path" do
          expect(HashUtil.fetch_value_at_path({"foo" => {"bar" => 3}}, ["foo"])).to eq({"bar" => 3})
        end

        it "raises a clear error when a key is not found, providing the missing key path in the error" do
          hash = {
            "other" => 1,
            "foo.bar.bazz" => "should not be returned",
            "foo" => {
              "other" => 2,
              "bar" => {
                "bazz" => 12,
                "other" => 3
              }
            }
          }

          expect {
            HashUtil.fetch_value_at_path(hash, ["bar"])
          }.to raise_error KeyError, a_string_including('["bar"]')

          expect {
            HashUtil.fetch_value_at_path(hash, ["bar", "bazz"])
          }.to raise_error KeyError, a_string_including('["bar"]')

          expect {
            HashUtil.fetch_value_at_path(hash, ["foo", "bazz", "bar"])
          }.to raise_error KeyError, a_string_including('["foo", "bazz"]')

          expect {
            HashUtil.fetch_value_at_path(hash, ["foo", "bar", "bazz2"])
          }.to raise_error KeyError, a_string_including('["foo", "bar", "bazz2"]')
        end

        it "raises a clear error when the value at a parent key is not a hash" do
          expect {
            HashUtil.fetch_value_at_path({"foo" => {"bar" => 3}}, ["foo", "bar", "bazz"])
          }.to raise_error KeyError, a_string_including('Value at key ["foo", "bar"] is not a `Hash` as expected; instead, was a `Integer`')

          expect {
            HashUtil.fetch_value_at_path({"foo" => 3}, ["foo", "bar", "bazz"])
          }.to raise_error KeyError, a_string_including('Value at key ["foo"] is not a `Hash` as expected; instead, was a `Integer`')
        end

        it "allows a block to be passed to provide a default value for missing keys" do
          hash = {
            "other" => 1,
            "foo.bar.bazz" => "should not be returned",
            "foo" => {
              "other" => 2,
              "bar" => {
                "bazz" => 12,
                "other" => 3
              }
            }
          }

          expect(HashUtil.fetch_value_at_path(hash, ["unknown"]) { 42 }).to eq 42
          expect(HashUtil.fetch_value_at_path(hash, ["foo", "bar", "unknown"]) { 37 }).to eq 37
          expect(HashUtil.fetch_value_at_path(hash, ["foo", "bar", "unknown", "bazz"]) { |key| "#{key.inspect} is missing" }).to eq '["foo", "bar", "unknown"] is missing'
        end

        it "does not use a provided block when for cases where a parent key is not a hash" do
          expect {
            HashUtil.fetch_value_at_path({"foo" => {"bar" => 3}}, ["foo", "bar", "bazz"]) { 3 }
          }.to raise_error KeyError, a_string_including('Value at key ["foo", "bar"] is not a `Hash` as expected; instead, was a `Integer`')
        end
      end

      describe ".fetch_leaf_values_at_path" do
        it "returns a list of values at the identified key" do
          values = HashUtil.fetch_leaf_values_at_path({"foo" => 17}, ["foo"])
          expect(values).to eq [17]

          values = HashUtil.fetch_leaf_values_at_path({"foo" => [17]}, ["foo"])
          expect(values).to eq [17]
        end

        it "handles nested paths by recursing through a nested hash" do
          hash = {
            "other" => 1,
            "foo.bar.bazz" => "should not be returned",
            "foo" => {
              "other" => 2,
              "bar" => {
                "bazz" => 12,
                "other" => 3
              }
            }
          }

          values = HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz"])

          expect(values).to eq [12]
        end

        it "returns `[]` when a parent key has an explicit `nil` value" do
          hash = {"foo" => {"bar" => nil}}
          values = HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz"])
          expect(values).to eq []

          hash = {"foo" => nil}
          values = HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz"])
          expect(values).to eq []
        end

        it "returns `[]` when a the nested path has an explicit `nil` value" do
          hash = {"foo" => {"bar" => nil}}
          values = HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar"])
          expect(values).to eq []
        end

        it "returns multiple values when the specified field is a list" do
          hash = {
            "other" => 1,
            "foo.bar.bazz" => "should not be returned",
            "foo" => {
              "other" => 2,
              "bar" => {
                "bazz" => [12, 3],
                "other" => 3
              }
            }
          }

          values = HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz"])

          expect(values).to eq [12, 3]
        end

        it "combines scalar values at the same path under a nested hash list as needed to return a flat list of values" do
          hash = {
            "foo" => {
              "bar" => [
                {"bazz" => 12},
                {"bazz" => 3}
              ]
            }
          }

          values = HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz"])

          expect(values).to eq [12, 3]
        end

        it "returns a flat list of values regardless of how many arrays are in the nested structure" do
          hash = {
            "foo" => [
              {
                "bar" => [
                  {"bazz" => [12, 3]},
                  {"bazz" => [4, 7]},
                  {"bazz" => []}
                ]
              },
              {"bar" => []},
              {"bar" => nil},
              {
                "bar" => [
                  {"bazz" => [1]},
                  {"bazz" => [9, 7]}
                ]
              }
            ]
          }

          values = HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz"])

          expect(values).to eq [12, 3, 4, 7, 1, 9, 7]
        end

        it "raises a clear error when a key is not found, providing the missing key path in the error" do
          hash = {
            "other" => 1,
            "foo.bar.bazz" => "should not be returned",
            "foo" => {
              "other" => 2,
              "bar" => {
                "bazz" => 12,
                "other" => 3
              }
            }
          }

          expect {
            HashUtil.fetch_leaf_values_at_path(hash, ["bar", "bazz"])
          }.to raise_error KeyError, a_string_including('["bar"]')

          expect {
            HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bazz", "bar"])
          }.to raise_error KeyError, a_string_including('["foo", "bazz"]')

          expect {
            HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz2"])
          }.to raise_error KeyError, a_string_including('["foo", "bar", "bazz2"]')
        end

        it "allows a default value block to be provided just like with `Hash#fetch`" do
          hash = {
            "other" => 1,
            "foo.bar.bazz" => "should not be returned",
            "foo" => {
              "other" => 2,
              "bar" => {
                "bazz" => 12,
                "other" => 3
              }
            }
          }

          expect(HashUtil.fetch_leaf_values_at_path(hash, ["bar", "bazz"]) { [] }).to eq []
          expect(HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bazz", "bar"]) { [] }).to eq []
          expect(HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bazz", "bar"]) { 3 }).to eq [3]
          expect(HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz2"]) { "abc" }).to eq ["abc"]
          expect(HashUtil.fetch_leaf_values_at_path(hash, ["foo", "bar", "bazz2"]) { |missing_key| missing_key }).to eq ["foo", "bar", "bazz2"]
        end

        it "raises a clear error when the value at a parent key is not a hash" do
          expect {
            HashUtil.fetch_leaf_values_at_path({"foo" => {"bar" => 3}}, ["foo", "bar", "bazz"])
          }.to raise_error KeyError, a_string_including('Value at key ["foo", "bar"] is not a `Hash` as expected; instead, was a `Integer`')

          expect {
            HashUtil.fetch_leaf_values_at_path({"foo" => 3}, ["foo", "bar", "bazz"])
          }.to raise_error KeyError, a_string_including('Value at key ["foo"] is not a `Hash` as expected; instead, was a `Integer`')
        end

        it "raises a clear error when the key is not a full path to a leaf" do
          expect {
            HashUtil.fetch_leaf_values_at_path({"foo" => {"bar" => 3}}, ["foo"])
          }.to raise_error KeyError, a_string_including('Key was not a path to a leaf field: ["foo"]')
        end
      end
    end
  end
end
