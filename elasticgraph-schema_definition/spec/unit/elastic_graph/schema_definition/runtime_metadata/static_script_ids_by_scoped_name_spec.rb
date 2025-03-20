# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #static_script_ids_by_scoped_name" do
      include_context "RuntimeMetadata support"

      it "has the ids and scoped names from our static scripts" do
        static_script_ids_by_scoped_name = define_schema.runtime_metadata.static_script_ids_by_scoped_name

        expect(static_script_ids_by_scoped_name.keys).to include("filter/by_time_of_day")
        expect(static_script_ids_by_scoped_name["filter/by_time_of_day"]).to match(/\Afilter_by_time_of_day_\w+\z/)
      end
    end
  end
end
