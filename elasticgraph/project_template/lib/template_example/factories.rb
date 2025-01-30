require "factory_bot"
require "faker"
require "date"
require_relative "shared_factories"

countries = %w[US CA AU JP]

FactoryBot.define do
  factory :company, parent: :indexed_type_base, traits: [:with_timestamps] do
    __typename { "Company" }
    name { Faker::Company.name }
  end
end

FactoryBot.define do
  factory :person, parent: :indexed_type_base, traits: [:with_timestamps] do
    __typename { "Person" }
    name { Faker::Name.name }
    groupId { Faker::Alphanumeric.alpha(number: 20) }
    birthdate { Faker::Date.between(from: Date.iso8601("1970-01-01"), to: Date.today).iso8601 }
    nationality { Faker::Base.sample(countries) }
    salary { build(:money) }
    parentIds { [] }
    companyId do
      # Zero or 1 company association
      Faker::Base.sample(nil, FactoryBot.build(:company)["id"])
    end
  end
end
