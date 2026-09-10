require "factory_bot"
require "faker"
require "yaml"

FactoryBot.define do
  factory :hash_base, class: Hash do
    initialize_with { attributes }
  end

  trait :uuid_id do
    id { Faker::Internet.uuid }
  end

  trait :versioned do
    # Use the current time as the version so that newly generated records always "win" over previously indexed records.
    __version { Time.now.to_i }
  end

  current_json_schema_version = nil

  factory :indexed_type_base, parent: :hash_base, traits: [:uuid_id, :versioned] do
    __typename { raise NotImplementedError, "You must supply __typename" }
    __json_schema_version do
      current_json_schema_version ||= begin
        json_schema_file = File.expand_path("../../config/schema/artifacts/json_schemas.yaml", __dir__)
        YAML.safe_load_file(json_schema_file).fetch("json_schema_version")
      end
    end
  end
end
