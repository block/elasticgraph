# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/datastore_core/index_definition"
require "elastic_graph/support/hash_util"
require "stringio"
require_relative "implementation_shared_examples"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      RSpec.describe RolloverIndexTemplate, :uses_datastore, :builds_indexer do
        # Use different index names than any other tests use, because most tests expect a specific index
        # configuration (based on `config/schema.graphql`) and we do not want to mess with it here.
        let(:index_prefix) { unique_index_name }
        let(:widgets_index_name) { "#{index_prefix}_widgets" }
        let(:components_index_name) { "#{index_prefix}_components" }
        let(:output_io) { StringIO.new }
        let(:schema_definition) do
          lambda do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime"
              t.index widgets_index_name do |i|
                i.rollover :monthly, "created_at"
              end
            end
          end
        end

        include_examples "an IndexDefinition implementation (integration specs)" do
          def configure_index(index)
            index.rollover :monthly, "created_at"
          end
        end

        describe "#delete_from_datastore", :builds_admin do
          let(:datastore_core) { build_datastore_core(schema_definition: schema_definition) }

          before do
            build_admin(datastore_core: datastore_core).cluster_configurator.configure_cluster(output_io)
          end

          it "deletes the rollover index definition" do
            index_definition = datastore_core.index_definitions_by_name.fetch(widgets_index_name)
            record = {
              "id" => "1234",
              "created_at" => "2019-06-02T12:00:00Z",
              "__typename" => "Widget",
              "__version" => 1,
              "__json_schema_version" => 1
            }
            index_name_for_writes = index_definition.index_name_for_writes(record)
            derive_index_from_template(record, datastore_core)

            expect {
              index_definition.delete_from_datastore(main_datastore_client)
            }.to change { main_datastore_client.get_index_template(index_definition.name)["template"] || {} }
              .from(a_hash_including(
                "mappings" => a_hash_including("properties" => a_hash_including("id", "created_at")),
                "settings" => a_kind_of(Hash)
              ))
              .to({})
              .and change { main_datastore_client.get_index(index_name_for_writes) }
              .from(a_hash_including(
                "mappings" => a_hash_including("properties" => a_hash_including("id", "created_at")),
                "settings" => a_kind_of(Hash)
              ))
              .to({})
          end

          it "ignores non-existing index template and index" do
            index_def_not_exist = index_def_named("does_not_exist", rollover: {
              timestamp_field_path: "created_at", frequency: :monthly
            })

            expect {
              index_def_not_exist.delete_from_datastore(main_datastore_client)
            }.not_to raise_error
          end
        end

        describe "related indices", :factories do
          it "returns an `Index` for each entry in `setting_overrides_by_timestamp` or `custom_timestamp_ranges` in config, with the name and normalized settings overridden" do
            schema_definition = lambda do |s|
              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "created_at", "DateTime"
                t.index "my_type", number_of_shards: 5, some: {other_setting: false} do |i|
                  i.rollover :monthly, "created_at"
                end
              end
            end

            datastore_core = build_datastore_core(schema_definition: schema_definition) do |config|
              config.with(index_definitions: {
                "my_type" => config_index_def_of(
                  setting_overrides: {
                    "common" => "override", # a setting not overridden by other setting overrides below.
                    "number_of_shards" => 12 # ...whereas this one is overridden below.
                  },
                  query_cluster: "other2",
                  setting_overrides_by_timestamp: {
                    "2020-01-01T00:00:00Z" => {
                      "number_of_shards" => 1,
                      "yet" => {"another" => {"setting" => true}}
                    },
                    "2020-02-01T00:00:00Z" => {
                      "number_of_shards" => 2,
                      "yet" => {"another" => {"setting" => true}}
                    }
                  },
                  custom_timestamp_ranges: [
                    {
                      "index_name_suffix" => "before_2015",
                      "lt" => "2015-01-01T00:00:00Z",
                      "setting_overrides" => {
                        "number_of_shards" => 3,
                        "yet" => {"another" => {"setting" => true}}
                      }
                    },
                    {
                      "index_name_suffix" => "2016_and_2017",
                      "gte" => "2016-01-01T00:00:00Z",
                      "lt" => "2018-01-01T00:00:00Z",
                      "setting_overrides" => {
                        "number_of_shards" => 4,
                        "yet" => {"another" => {"setting" => true}}
                      }
                    }
                  ]
                )
              })
            end

            index = datastore_core.index_definitions_by_name.fetch("my_type")
            related_rollover_indices = index.related_rollover_indices(main_datastore_client)
            # No indexes exist to query yet, so `known_related_query_rollover_indices` should be empty.
            expect(index.known_related_query_rollover_indices).to eq([])

            expect(related_rollover_indices.size).to eq 4

            expect(related_rollover_indices[0]).to be_a RolloverIndex
            expect(related_rollover_indices[0].name).to eq "my_type_rollover__2020-01"
            expect(related_rollover_indices[0].cluster_to_query).to eq "other2"
            expect(related_rollover_indices[0].time_set).to eq(Support::TimeSet.of_range(
              gte: ::Time.iso8601("2020-01-01T00:00:00Z"),
              lt: ::Time.iso8601("2020-02-01T00:00:00Z")
            ))
            expect(related_rollover_indices[0].flattened_env_setting_overrides).to include(
              "index.common" => "override",
              "index.number_of_shards" => 1,
              "index.yet.another.setting" => true
            )

            expect(related_rollover_indices[1]).to be_a RolloverIndex
            expect(related_rollover_indices[1].name).to eq "my_type_rollover__2020-02"
            expect(related_rollover_indices[1].cluster_to_query).to eq "other2"
            expect(related_rollover_indices[1].time_set).to eq(Support::TimeSet.of_range(
              gte: ::Time.iso8601("2020-02-01T00:00:00Z"),
              lt: ::Time.iso8601("2020-03-01T00:00:00Z")
            ))
            expect(related_rollover_indices[1].flattened_env_setting_overrides).to include(
              "index.common" => "override",
              "index.number_of_shards" => 2,
              "index.yet.another.setting" => true
            )

            expect(related_rollover_indices[2]).to be_a RolloverIndex
            expect(related_rollover_indices[2].name).to eq "my_type_rollover__before_2015"
            expect(related_rollover_indices[2].cluster_to_query).to eq "other2"
            expect(related_rollover_indices[2].time_set).to eq(Support::TimeSet.of_range(
              lt: ::Time.iso8601("2015-01-01T00:00:00Z")
            ))
            expect(related_rollover_indices[2].flattened_env_setting_overrides).to include(
              "index.common" => "override",
              "index.number_of_shards" => 3,
              "index.yet.another.setting" => true
            )

            expect(related_rollover_indices[3]).to be_a RolloverIndex
            expect(related_rollover_indices[3].name).to eq "my_type_rollover__2016_and_2017"
            expect(related_rollover_indices[3].cluster_to_query).to eq "other2"
            expect(related_rollover_indices[3].time_set).to eq(Support::TimeSet.of_range(
              gte: ::Time.iso8601("2016-01-01T00:00:00Z"),
              lt: ::Time.iso8601("2018-01-01T00:00:00Z")
            ))
            expect(related_rollover_indices[3].flattened_env_setting_overrides).to include(
              "index.common" => "override",
              "index.number_of_shards" => 4,
              "index.yet.another.setting" => true
            )
          end

          it "supports nested rollover timestamp fields" do
            schema_definition = lambda do |s|
              s.object_type "NestedFields" do |t|
                t.field "created_at", "DateTime"
              end

              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "nested_fields", "NestedFields"
                t.index "my_type", number_of_shards: 5, some: {other_setting: false} do |i|
                  i.rollover :monthly, "nested_fields.created_at"
                end
              end
            end

            datastore_core = build_datastore_core(schema_definition: schema_definition) do |config|
              config.with(index_definitions: {
                "my_type" => config_index_def_of(
                  setting_overrides: {
                    "common" => "override", # a setting not overridden by other setting overrides below.
                    "number_of_shards" => 12 # ...whereas this one is overridden below.
                  },
                  query_cluster: "other2",
                  setting_overrides_by_timestamp: {
                    "2020-01-01T00:00:00Z" => {
                      "number_of_shards" => 1,
                      "yet" => {"another" => {"setting" => true}}
                    },
                    "2020-02-01T00:00:00Z" => {
                      "number_of_shards" => 2,
                      "yet" => {"another" => {"setting" => true}}
                    }
                  },
                  custom_timestamp_ranges: []
                )
              })
            end

            index = datastore_core.index_definitions_by_name.fetch("my_type")
            related_rollover_indices = index.related_rollover_indices(main_datastore_client)
            # No indexes exist to query yet, so `known_related_query_rollover_indices` should be empty.
            expect(index.known_related_query_rollover_indices).to eq([])

            expect(related_rollover_indices.size).to eq 2

            expect(related_rollover_indices[0]).to be_a RolloverIndex
            expect(related_rollover_indices[0].name).to eq "my_type_rollover__2020-01"
            expect(related_rollover_indices[0].cluster_to_query).to eq "other2"
            expect(related_rollover_indices[0].time_set).to eq(Support::TimeSet.of_range(
              gte: ::Time.iso8601("2020-01-01T00:00:00Z"),
              lt: ::Time.iso8601("2020-02-01T00:00:00Z")
            ))
            expect(related_rollover_indices[0].flattened_env_setting_overrides).to include(
              "index.common" => "override",
              "index.number_of_shards" => 1,
              "index.yet.another.setting" => true
            )

            expect(related_rollover_indices[1]).to be_a RolloverIndex
            expect(related_rollover_indices[1].name).to eq "my_type_rollover__2020-02"
            expect(related_rollover_indices[1].cluster_to_query).to eq "other2"
            expect(related_rollover_indices[1].time_set).to eq(Support::TimeSet.of_range(
              gte: ::Time.iso8601("2020-02-01T00:00:00Z"),
              lt: ::Time.iso8601("2020-03-01T00:00:00Z")
            ))
            expect(related_rollover_indices[1].flattened_env_setting_overrides).to include(
              "index.common" => "override",
              "index.number_of_shards" => 2,
              "index.yet.another.setting" => true
            )
          end

          it "returns any indices that have been auto-created from the rollover template, while ignoring other indices" do
            datastore_core = build_datastore_core(schema_definition: schema_definition)
            record = Support::HashUtil.stringify_keys(build(:widget))
            derive_index_from_template(record, datastore_core)

            index_def = datastore_core.index_definitions_by_name.fetch(widgets_index_name)
            related_rollover_indices = index_def.related_rollover_indices(main_datastore_client)
            expect(index_def.known_related_query_rollover_indices).to eq(related_rollover_indices)

            expect(related_rollover_indices.size).to eq 1
            expect(related_rollover_indices.first).to be_a(RolloverIndex)
            expect(related_rollover_indices.first.name).to eq index_def.index_name_for_writes(record)
            expect(main_datastore_client.list_indices_matching("*").size).to be > 1 # demonstrate there were other indices that were ignored
          end

          it "prefers the config settings defined in `setting_overrides_by_timestamp`/`custom_timestamp_ranges` over the existing settings on auto-created indices" do
            datastore_core = build_datastore_core(schema_definition: schema_definition)
            record = Support::HashUtil.stringify_keys(build(:widget))
            derive_index_from_template(record, datastore_core)

            datastore_core = build_datastore_core(schema_definition: schema_definition) do |config|
              config.with(index_definitions: config.index_definitions.merge(widgets_index_name => config_index_def_of(setting_overrides_by_timestamp: {
                record.fetch("created_at") => {
                  "number_of_shards" => 7,
                  "yet" => {"another" => {"setting" => true}}
                }
              })))
            end

            index_def = datastore_core.index_definitions_by_name.fetch(widgets_index_name)
            related_rollover_indices = index_def.related_rollover_indices(main_datastore_client)
            expect(index_def.known_related_query_rollover_indices).to eq(related_rollover_indices)

            expect(related_rollover_indices.size).to eq 1
            expect(related_rollover_indices.first).to be_a(RolloverIndex)
            expect(related_rollover_indices.first.name).to eq index_def.index_name_for_writes(record)
            expect(related_rollover_indices.first.flattened_env_setting_overrides).to include(
              "index.number_of_shards" => 7,
              "index.yet.another.setting" => true
            )
          end

          it "returns an empty array, if no indices have been autocreated and config has no overrides" do
            schema_definition = lambda do |s|
              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "created_at", "DateTime"
                t.index "my_type" do |i|
                  i.rollover :monthly, "created_at"
                end
              end
            end

            datastore_core = build_datastore_core(schema_definition: schema_definition) do |config|
              config.with(index_definitions: config.index_definitions.dup.clear)
            end

            index = datastore_core.index_definitions_by_name.fetch("my_type")

            expect(index.related_rollover_indices(main_datastore_client)).to be_empty
            expect(index.known_related_query_rollover_indices).to be_empty
          end

          it "memoizes the `#known_related_query_rollover_indices` result so we only ever query the datastore once for that info" do
            index = build_datastore_core(schema_definition: schema_definition).index_definitions_by_name.fetch(widgets_index_name)

            expect {
              index.known_related_query_rollover_indices
            }.to make_datastore_calls("main").to include(a_string_starting_with("GET /_cat/indices/#{widgets_index_name}_rollover__%2A"))

            expect {
              index.known_related_query_rollover_indices
              index.known_related_query_rollover_indices
            }.to make_no_datastore_calls("main")
          end

          it "returns `[]` from `#known_related_query_rollover_indices` when there is no configured datastore cluster to query" do
            index = build_datastore_core(schema_definition: schema_definition) do |config|
              config.with(index_definitions: {
                widgets_index_name => config_index_def_of(query_cluster: nil),
                components_index_name => config_index_def_of(query_cluster: nil)
              })
            end.index_definitions_by_name.fetch(widgets_index_name)

            expect(index.known_related_query_rollover_indices).to be_empty
          end

          context "when the index definition configuration disagrees with what the indices we have in the datastore" do
            let(:index_name) { "#{index_prefix}_my_type" }

            it "ignores (from `#known_related_query_rollover_indices` but not `#related_rollover_indices`) config-defined indices that do not exist in the datastore" do
              datastore_core = build_datastore_core_for(rollover_frequency: :yearly, index_config: config_index_def_of(
                setting_overrides_by_timestamp: {
                  "2020-01-01T00:00:00Z" => {}
                },
                custom_timestamp_ranges: [
                  {
                    "index_name_suffix" => "before_2015",
                    "lt" => "2015-01-01T00:00:00Z",
                    "setting_overrides" => {}
                  }
                ]
              ))

              record = Support::HashUtil.stringify_keys(build(:widget, created_at: "2019-08-01T00:00:00Z"))
              derive_index_from_template(record, datastore_core)

              index = datastore_core.index_definitions_by_name.fetch(index_name)

              expect(index.related_rollover_indices(main_datastore_client).map(&:name)).to contain_exactly("#{index_name}_rollover__2019", "#{index_name}_rollover__2020", "#{index_name}_rollover__before_2015")
              expect(index.known_related_query_rollover_indices.map(&:name)).to contain_exactly("#{index_name}_rollover__2019")
            end

            it "includes indices with open ranges in both `#known_related_query_rollover_indices` and `#related_rollover_indices` when the index is defined in config and exists in the datastore" do
              datastore_core = build_datastore_core_for(rollover_frequency: :yearly, index_config: config_index_def_of(
                custom_timestamp_ranges: [
                  {
                    "index_name_suffix" => "before_2015",
                    "lt" => "2015-01-01T00:00:00Z",
                    "setting_overrides" => {}
                  }
                ]
              ))

              record = Support::HashUtil.stringify_keys(build(:widget, created_at: "2014-08-01T00:00:00Z"))
              derive_index_from_template(record, datastore_core)

              index = datastore_core.index_definitions_by_name.fetch(index_name)

              expect(index.related_rollover_indices(main_datastore_client).map(&:name)).to contain_exactly("#{index_name}_rollover__before_2015")
              expect(index.known_related_query_rollover_indices.map(&:name)).to contain_exactly("#{index_name}_rollover__before_2015")
            end

            it "ignores (from both `#known_related_query_rollover_indices` and `#related_rollover_indices`) datastore indices with custom suffixes that have no corresponding definition in config" do
              datastore_core1 = build_datastore_core_for(rollover_frequency: :yearly, index_config: config_index_def_of(
                setting_overrides_by_timestamp: {
                  "2020-01-01T00:00:00Z" => {}
                },
                custom_timestamp_ranges: [
                  {
                    "index_name_suffix" => "before_2015",
                    "lt" => "2015-01-01T00:00:00Z",
                    "setting_overrides" => {}
                  }
                ]
              ))

              record = Support::HashUtil.stringify_keys(build(:widget, created_at: "2014-08-01T00:00:00Z"))
              derive_index_from_template(record, datastore_core1)

              record = Support::HashUtil.stringify_keys(build(:widget, created_at: "2020-08-01T00:00:00Z"))
              derive_index_from_template(record, datastore_core1)

              datastore_core2 = build_datastore_core_for(rollover_frequency: :yearly, index_config: config_index_def_of(
                setting_overrides_by_timestamp: {
                  "2020-01-01T00:00:00Z" => {}
                }
              ))

              index = datastore_core2.index_definitions_by_name.fetch(index_name)

              expect(index.related_rollover_indices(main_datastore_client).map(&:name)).to contain_exactly("#{index_name}_rollover__2020")
              expect(index.known_related_query_rollover_indices.map(&:name)).to contain_exactly("#{index_name}_rollover__2020")
            end

            it "ignores (from both `#known_related_query_rollover_indices` and `#related_rollover_indices`) datastore indices created for a different rollover granularity than what is currently defined" do
              datastore_core1 = build_datastore_core_for(rollover_frequency: :yearly)
              record = Support::HashUtil.stringify_keys(build(:widget, created_at: "2017-08-01T00:00:00Z"))
              derive_index_from_template(record, datastore_core1)

              datastore_core2 = build_datastore_core_for(rollover_frequency: :monthly)
              index = datastore_core2.index_definitions_by_name.fetch(index_name)

              expect(index.related_rollover_indices(main_datastore_client).map(&:name)).to be_empty
              expect(index.known_related_query_rollover_indices.map(&:name)).to be_empty
            end

            def build_datastore_core_for(rollover_frequency:, index_config: config_index_def_of)
              schema_definition = lambda do |s|
                s.object_type "Widget" do |t|
                  t.field "id", "ID!"
                  t.field "created_at", "DateTime"
                  t.index index_name do |i|
                    i.rollover rollover_frequency, "created_at"
                  end
                end
              end

              build_datastore_core(schema_definition: schema_definition) do |config|
                config.with(index_definitions: {index_name => index_config})
              end
            end
          end

          describe "rollover frequencies" do
            example_ranges_by_frequency = {
              yearly: ["2020-01-01T00:00:00Z".."2021-01-01T00:00:00Z", "2021-01-01T00:00:00Z".."2022-01-01T00:00:00Z"],
              monthly: ["2020-09-01T00:00:00Z".."2020-10-01T00:00:00Z", "2021-10-01T00:00:00Z".."2021-11-01T00:00:00Z"],
              daily: ["2020-09-09T00:00:00Z".."2020-09-10T00:00:00Z", "2021-10-12T00:00:00Z".."2021-10-13T00:00:00Z"],
              hourly: ["2020-09-09T09:00:00Z".."2020-09-09T10:00:00Z", "2021-10-12T16:00:00Z".."2021-10-12T17:00:00Z"]
            }

            after(:context) do
              # verify `example_ranges_by_frequency` covers all supported frequencies
              expect(example_ranges_by_frequency.keys).to match_array(RolloverIndexTemplate::TIME_UNIT_BY_FREQUENCY.keys)
            end

            example_ranges_by_frequency.each do |frequency, (range_for_single_digits, range_for_double_digits)|
              context "when the index is configured with #{frequency} rollover" do
                let(:indexer) { build_indexer(datastore_core: datastore_core) }
                let(:datastore_core) do
                  schema_definition = lambda do |s|
                    s.object_type "Widget" do |t|
                      t.field "id", "ID!"
                      t.field "created_at", "DateTime"
                      t.index widgets_index_name do |i|
                        i.rollover frequency, "created_at"
                      end
                    end
                  end

                  build_datastore_core(schema_definition: schema_definition) do |config|
                    config.with(index_definitions: config.index_definitions.dup.clear)
                  end
                end

                before do
                  # The tests below use a slightly different schema from our main test schema, in order to
                  # exercise different relationships (e.g. with foreign keys pointing both directions for
                  # any kind of relationship). As a result, calls to `validate_mapping_completeness_of!` will
                  # raise exceptions. Since the mapping difference is intentional in these tests, we want
                  # to silence the exception here, which we can do by stubbing it to be a no-op.
                  allow(indexer.datastore_router).to receive(:validate_mapping_completeness_of!)
                end

                it "is correctly able to infer the timestamp range from indices created from timestamps with both single and double digit numbers" do
                  index_into(
                    indexer,
                    # Here we use all zero-leading single digit numbers in the time. We do that so that our
                    # test covers an odd Ruby edge case: in some contexts, Ruby interprets a leading `0` to mean
                    # a numeric string is an octal string:
                    #
                    # 2.7.4 :005 > Integer("07")
                    #  => 7
                    # 2.7.4 :006 > Integer("011")
                    #  => 9
                    # 2.7.4 :007 > Integer("09")
                    # Traceback (most recent call last):
                    #         5: from /Users/myron/.rvm/rubies/ruby-2.7.4/bin/irb:23:in `<main>'
                    #         4: from /Users/myron/.rvm/rubies/ruby-2.7.4/bin/irb:23:in `load'
                    #         3: from /Users/myron/.rvm/rubies/ruby-2.7.4/lib/ruby/gems/2.7.0/gems/irb-1.2.6/exe/irb:11:in `<top (required)>'
                    #         2: from (irb):7
                    #         1: from (irb):7:in `Integer'
                    # ArgumentError (invalid value for Integer(): "09")
                    #
                    # As shown here, `09` is particularly problematic because it isn't a valid octal string, and blows up.
                    # So here we use that for all numbers (except year), to verify that our logic handles it fine.
                    build(:widget, created_at: "2020-09-09T09:09:09Z"),
                    # ...vs here we use double digit numbers in the time.
                    build(:widget, created_at: "2021-10-12T16:37:52Z")
                  )

                  index = datastore_core.index_definitions_by_name.fetch(widgets_index_name)
                  rollover_indices = index.known_related_query_rollover_indices.sort_by(&:name)

                  expect(rollover_indices.size).to eq(2)
                  expect(rollover_indices.first.time_set).to eq(Support::TimeSet.of_range(
                    gte: ::Time.iso8601(range_for_single_digits.begin),
                    lt: ::Time.iso8601(range_for_single_digits.end)
                  ))
                  expect(rollover_indices.last.time_set).to eq(Support::TimeSet.of_range(
                    gte: ::Time.iso8601(range_for_double_digits.begin),
                    lt: ::Time.iso8601(range_for_double_digits.end)
                  ))
                end
              end
            end
          end
        end

        def derive_index_from_template(record, datastore_core)
          indexer = build_indexer(datastore_core: datastore_core)
          # The tests above use a slightly different schema definition than the main test schema definition,
          # and as a result calls to `validate_mapping_completeness_of!` will fail. This is intentional, and
          # we want to allow it, so here we stub it to be a no-op.
          allow(indexer.datastore_router).to receive(:validate_mapping_completeness_of!)

          index_into(indexer, record)
        end

        def index_def_named(name, rollover: nil)
          runtime_metadata = SchemaArtifacts::RuntimeMetadata::IndexDefinition.new(
            route_with: nil,
            rollover: SchemaArtifacts::RuntimeMetadata::IndexDefinition::Rollover.new(**rollover),
            default_sort_fields: [],
            current_sources: [SELF_RELATIONSHIP_NAME],
            fields_by_path: {}
          )

          DatastoreCore::IndexDefinition.with(
            name: name,
            config: datastore_core.config,
            runtime_metadata: runtime_metadata,
            datastore_clients_by_name: datastore_core.clients_by_name
          )
        end
      end
    end
  end
end
