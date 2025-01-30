require_relative "factories"

module TemplateExample
  module FakeDataBatchGenerator
    def self.generate_fake_people(count)
      people = FactoryBot.build_list(:person, count)

      people.each_slice(5).each do |(parent1, parent2), *kids|
        parent_ids = [parent1, parent2].compact.map { |p| p.fetch(:id) }
        kids.each { |k| k[:parentIds] = parent_ids }
      end

      people
    end

    def self.generate_fake_companies(count)
      FactoryBot.build_list(:company, count)
    end
  end
end
