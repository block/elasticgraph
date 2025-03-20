# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Provides test harness support for testing indexing preparers. Instead of calling
# an index preparer directly, this tests it via the overall `RecordPreparer`, which
# gives us confidence that the index preparer is used as expected from the `RecordPreparer`.
# For example, to see your indexing preparer being used, this requires that it is registered
# on your scalar type correctly, whereas if this directly called your indexing preparer
# it wouldn't require it to be correctly registered.
RSpec.shared_context "indexing preparer support" do |scalar_type|
  before(:context) do
    @record_preparer = build_indexer(clients_by_name: {}, schema_definition: lambda do |schema|
      schema.object_type "MyType" do |t|
        t.field "id", "ID!"
        t.field "scalar", scalar_type
        t.field "array_of_scalar", "[#{scalar_type}]"
        t.field "array_of_array_of_scalar", "[[#{scalar_type}]]"
        t.field "array_of_object", "[Object]" do |f|
          f.mapping type: "object"
        end
        t.index "my_type"
      end

      schema.object_type "Object" do |t|
        t.field "scalar", scalar_type
      end
    end).record_preparer_factory.for_latest_json_schema_version
  end

  def prepare_scalar_value(value)
    prepare_field_value("scalar", value)
  end

  def prepare_array_values(values)
    prepare_field_value("array_of_scalar", values)
  end

  def prepare_array_of_array_of_values(values)
    prepare_field_value("array_of_array_of_scalar", values)
  end

  def prepare_array_of_objects_of_values(values)
    input_objects = values.map { |v| {"scalar" => v} }
    output_objects = prepare_field_value("array_of_object", input_objects)
    expect(output_objects.map(&:keys)).to all eq(["scalar"])
    output_objects.map { |o| o.fetch("scalar") }
  end

  private

  def prepare_field_value(field, value)
    record = @record_preparer.prepare_for_index("MyType", build_record(field => value))
    record.fetch(field)
  end

  def build_record(overrides)
    {
      "id" => "some-id",
      "scalar" => nil,
      "array_of_scalar" => nil,
      "array_of_array_of_scalar" => nil
    }.merge(overrides)
  end
end
