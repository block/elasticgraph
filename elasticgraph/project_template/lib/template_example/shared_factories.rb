require "factory_bot"
require "faker"

currencies = %w[USD CAD]

FactoryBot.define do
  factory :hash_base, class: Hash do
    initialize_with { attributes }
  end

  trait :uuid_id do
    id { Faker::Internet.uuid }
  end

  trait :versioned do
    __version { Faker::Number.between(from: 1, to: 10) }
  end

  trait :with_created_at do
    createdAt { Faker::Time.between(from: Date.today - 1800, to: Date.today).utc.iso8601 }
  end

  trait :with_timestamps do
    createdAt { Faker::Time.between(from: Date.today - 1800, to: Date.today).utc.iso8601 }
    updatedAt { Faker::Time.between(from: Date.today - 1800, to: Date.today).utc.iso8601 }
  end

  factory :money, parent: :hash_base do
    amount { Faker::Number.between(from: 500, to: 9999999) }
    currency { Faker::Base.sample(currencies) }
  end

  json_schema_file = ::File.expand_path("../../config/schema/artifacts/json_schemas.yaml", __dir__)
  current_json_schema_version = ::YAML.safe_load_file(json_schema_file).fetch("json_schema_version")

  factory :indexed_type_base, parent: :hash_base, traits: [:uuid_id, :versioned] do
    __typename { raise NotImplementedError, "You must supply __typename" }
    __json_schema_version { current_json_schema_version }
  end
end
