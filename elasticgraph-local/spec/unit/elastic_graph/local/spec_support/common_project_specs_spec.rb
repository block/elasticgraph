# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/local/spec_support/common_project_specs"

module ElasticGraph
  module Local
    RSpec.describe "ElasticGraph project shared examples", :factories do
      include_examples "an ElasticGraph project",
        repo_root: CommonSpecHelpers::REPO_ROOT,
        settings_dir: "config/settings",
        use_settings_yaml: "development.yaml",
        factory_iterations: 2,
        # :embedded_person and :embedded_company are for use as embedded field values (e.g.
        # `Widget.inventor`, `Manufacturer.ceo`). They lack `__version` and other fields
        # required for indexing directly, so we exclude them from the indexed record validation.
        ignored_factories: [:embedded_person, :embedded_company]
    end
  end
end
