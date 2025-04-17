# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# activesupport 7.2.0 was recently (2024-08-09) released and broke factory_bot.
# To work around it we need to require it here, as per:
# https://github.com/thoughtbot/factory_bot/issues/1685
#
# TODO: once factory_bot has had a new release with a fix, remove this require (we don't use activesupport).
require "active_support"
require "factory_bot"
require "faker"
require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/support/hash_util"

# A counter that we increment for the `__version` value on each new factory-generated record.
version_counter = 0

RSpec.shared_context "factories" do
  # we use `prepend_before` so this runs before other `before` hooks.
  prepend_before do |ex|
    # Make faker usage deterministic, based on the `full_description` string of the
    # RSpec example. `String#sum` is being used purely for speed, as we do not
    # need a particularly even distribution in random number seeds.
    Faker::Config.random = Random.new(ex.full_description.sum)

    # We reset the version counter to 0 here so that the version values used in a test don't depend on the order
    # the test runs. That's essential to give us deterministic Elasticsearch request bodies.
    version_counter = 0
  end

  def build(type, *args)
    # Allow callers to do `build(:part, ...)` to randomly (but deterministically) get
    # either an `:electrical_part` or a `:mechanical_part`.
    type = Faker::Base.sample(%i[electrical_part mechanical_part]) if type == :part

    super(type, *args)
  end

  def build_upsert_event(type, **attributes)
    record = ElasticGraph::Support::HashUtil.stringify_keys(build(type, **attributes))
    ElasticGraph::Indexer::TestSupport::Converters.upsert_event_for(record)
  end
end

RSpec.configure do |config|
  config.include_context "factories", :factories
  config.include FactoryBot::Syntax::Methods, :factories
end

module ElasticGraphSpecSupport
  CURRENCIES_BY_CODE = {
    "USD" => {symbol: "$", unit: "dollars", name: "United States Dollar", primary_continent: "North America", introduced_on: "1792-04-02"},
    "CAD" => {symbol: "$", unit: "dollars", name: "Canadian Dollar", primary_continent: "North America", introduced_on: "1868-01-01"},
    "GBP" => {symbol: "£", unit: "pounds", name: "British Pound Sterling", primary_continent: "Europe", introduced_on: "0800-01-01"},
    "JPY" => {symbol: "¥", unit: "yen", name: "Japanese Yen", primary_continent: "Asia", introduced_on: "1871-01-01"}
  }
end

FactoryBot.define do
  factory :hash_base, class: Hash do
    initialize_with do
      attributes.except(*__exclude_fields)
    end

    transient do
      __exclude_fields { [] }
    end
  end

  factory :indexed_type, parent: :hash_base do
    # When building new factory records, we normally expect each new record to automatically "win"
    # over previously generated records, so we use a counter here that we increment for each
    # factory-generated record.
    #
    # For tests that really care about the version, they override it to control this more tightly.
    __version { version_counter += 1 }
    __typename { raise NotImplementedError, "You must supply __typename." }
    __json_schema_version { 1 }
    id { Faker::Alphanumeric.alpha(number: 20) }
  end

  factory :geo_location, parent: :hash_base do
    __typename { "GeoLocation" }
    # latitude is -90.0 to +90.0
    latitude { Faker::Number.between(from: -90.0, to: 90.0) }
    # longitude is -180.0 to +180.0
    longitude { Faker::Number.between(from: -180.0, to: 180.0) }
  end

  currencies_by_code = ElasticGraphSpecSupport::CURRENCIES_BY_CODE
  factory :money, parent: :hash_base do
    __typename { "Money" }
    currency { Faker::Base.sample(currencies_by_code.keys) }
    amount_cents { Faker::Number.between(from: 100, to: 10000) }
  end
end

require "elastic_graph/spec_support/factories/teams"
require "elastic_graph/spec_support/factories/widgets"
