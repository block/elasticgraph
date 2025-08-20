# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "date"

# Note: it is *essential* that all factories defined here generate records
# deterministically, in order for the request bodies to (and responses from)
# the datastore to not change between VCR cassettes being recorded and replayed.

# Note: in our JSON Schema, `__typename` is defined for ALL object types but is only _required_ on abstract object types
# (e.g. for type unions or interfaces). However, clients that publish using egpublisher always include it on every object
# type (because of how the code gen works).
#
# In addition, in the factories here we require it on all indexed types (the ones with `parent: :graph_base`) because
# `Indexer::TestSupport::Converters.upsert_event_for` relies on it in order to build the event envelope. That process strips the
# `__typename` from the `record`.
#
# We intentionally include `__typename` in many non-indexed object types here in order to simulate it being set on them
# (since that's what our publishers do) in order to exercise edge cases related to `__typename`. However, we haven't
# included it in all object types since some publishers could omit it.

# A fixed date we can use instead of `Date.today` in our factories.
# As mentioned above, our factories are intended to be deterministic, and we need to avoid using `Date.today` (or `Time.now`) to
# ensure determinism.
recent_date = ::Date.new(2023, 11, 25)

FactoryBot.define do
  factory :widget_options, parent: :hash_base do
    __typename { "WidgetOptions" }
    size { Faker::Base.sample(["SMALL", "MEDIUM", "LARGE"]) }
    the_size { size }
    color { Faker::Base.sample(["RED", "GREEN", "BLUE"]) }
    is_draft { false }
  end

  factory :person, parent: :hash_base do
    __typename { "Person" }
    name { Faker::Name.name }
    nationality { Faker::Nation.nationality }
  end

  factory :company, parent: :hash_base do
    __typename { "Company" }
    name { Faker::Company.name }
    stock_ticker { name[0..3].upcase }
  end

  factory :position, parent: :hash_base do
    # omitting `__typename` here intentionally; a test in elasticgraph-indexer/spec/unit/elastic_graph/indexer/operation/upsert_spec.rb
    # fails if we include it because the test uses the entire `event["record"]` in an assertion for simplicity.
    #
    # __typename { "Position" }

    x { Faker::Number.between(from: -100, to: 100) }
    y { Faker::Number.between(from: -100, to: 100) }
  end

  factory :geo_shape, parent: :hash_base do
    type { "Point" }
    coordinates { ::Array.new(2) { Faker::Number.between(from: -100, to: 100) } }
  end

  factory :address_timestamps, parent: :hash_base do
    # omitting `__typename` here intentionally; a test in elasticgraph-graphql/spec/acceptance/datastore_spec.rb
    # fails if we include it because the test uses the entire `event["record"]` in an assertion for simplicity.
    #
    # __typename { "AddressTimestamps" }
    created_at { Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601 }
  end

  currencies_by_code = ElasticGraphSpecSupport::CURRENCIES_BY_CODE

  factory :workspace_widget, parent: :hash_base do
    id { Faker::Alphanumeric.alpha(number: 20) }
    created_at { Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601 }
  end

  factory :widget, parent: :indexed_type do
    __typename { "Widget" }
    workspace_id { Faker::Alphanumeric.alpha(number: 6) }
    amount_cents { Faker::Number.between(from: 100, to: 10000) }
    cost { build(:money, amount_cents: amount_cents, currency: cost_currency) }
    cost_currency_unit { cost&.fetch(:currency)&.then { |code| currencies_by_code.dig(code, :unit) } }
    cost_currency_name { cost&.fetch(:currency)&.then { |code| currencies_by_code.dig(code, :name) } }
    cost_currency_primary_continent { cost&.fetch(:currency)&.then { |code| currencies_by_code.dig(code, :primary_continent) } }
    cost_currency_introduced_on { cost&.fetch(:currency)&.then { |code| currencies_by_code.dig(code, :introduced_on) } }
    cost_currency_symbol { cost&.fetch(:currency)&.then { |code| currencies_by_code.dig(code, :symbol) } }
    name { Faker::Device.model_name }
    name_text { name }
    description { "this is #{Faker::Device.model_name}" }
    created_at { Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601 }
    created_at_time_of_day { ::Time.iso8601(created_at).strftime("%H:%M:%S") }
    created_on { ::Time.iso8601(created_at).to_date.iso8601 }
    release_timestamps { Array.new(Faker::Number.between(from: 0, to: 4)) { Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601 } }
    release_dates { release_timestamps.map { |ts| ::Time.iso8601(ts).to_date.iso8601 } }
    options { build :widget_options }
    the_options { options }

    component_ids do
      components.map { |c| c.fetch(:id) }
    end

    inventor { build Faker::Base.sample([:person, :company]) }
    named_inventor { inventor }
    weight_in_ng { Faker::Number.between(from: 2**51, to: (2**53) - 1) }
    weight_in_ng_str { Faker::Number.between(from: 2**60, to: 2**61) }
    tags { Array.new(Faker::Number.between(from: 0, to: 4)) { Faker::Alphanumeric.alpha(number: 6) } }
    amounts { Array.new(Faker::Number.between(from: 0, to: 4)) { Faker::Number.between(from: 100, to: 10000) } }
    fees { build_list(:money, Faker::Number.between(from: 0, to: 4)) }
    metadata do
      selection = Faker::Base.sample([:meta_number, :meta_id, :meta_names, :meta_json])
      send(selection)
    end

    transient do
      components { [] }
      cost_currency { Faker::Base.sample(currencies_by_code.keys) }
      meta_number { Faker::Number.between(from: 0, to: 999999999) }
      meta_id { Faker::Alphanumeric.alpha(number: 8) }
      meta_names { 3.times.map { Faker::Name.name } }
      meta_json do
        json = Faker::Json.shallow_json(width: 3, options: {key: "Name.first_name", value: "Name.last_name"})
        ::JSON.parse(json)
      end
    end
  end

  factory :widget_workspace, parent: :indexed_type do
    __typename { "WidgetWorkspace" }
    widget { build(:workspace_widget) }
    name { Faker::Job.field }
  end

  factory :manufacturer, parent: :indexed_type do
    __typename { "Manufacturer" }
    name { Faker::Company.name }
    created_at { Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601 }
  end

  factory :address, parent: :indexed_type do
    __typename { "Address" }
    full_address { Faker::Address.full_address }
    manufacturer_id { manufacturer&.fetch(:id) }
    timestamps { build(:address_timestamps, created_at: created_at) }
    geo_location { build(:geo_location) }
    shapes { [build(:geo_shape)] }

    transient do
      manufacturer { nil }
      created_at { Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601 }
    end
  end

  factory :part_base, parent: :indexed_type do
    name do
      material = Faker::Base.sample(%w[oak pine iron gold steel copper silicon plastic wood maple])
      type = Faker::Base.sample(%w[gasket dowel rod screw clasp zipper snap button])
      "#{material} #{type} #{Faker::Number.between(from: 10000, to: 99999)}"
    end
    manufacturer_id { manufacturer&.fetch(:id) }
    created_at { Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601 }

    transient do
      manufacturer { nil }
    end

    factory :electrical_part do
      __typename { "ElectricalPart" }
      voltage { Faker::Base.sample([110, 120, 220, 240]) }
    end

    factory :mechanical_part do
      __typename { "MechanicalPart" }
      material { Faker::Base.sample(["ALLOY", "CARBON_FIBER"]) }
    end
  end

  factory :component, parent: :indexed_type do
    __typename { "Component" }
    name { Faker::ElectricalComponents.active }
    created_at { Faker::Time.between(from: recent_date - 30, to: recent_date).utc.iso8601 }
    position { build :position }
    owner_ids { [] }
    owner_id { owner_ids.first }

    part_ids do
      parts.map { |part| part.fetch(:id) }
    end

    tags { Array.new(Faker::Number.between(from: 0, to: 4)) { Faker::Alphanumeric.alpha(number: 6) } }

    transient do
      parts { [] }
    end
  end
end
