# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin"
require "elastic_graph/spec_support/builds_datastore_core"

module ElasticGraph
  module BuildsAdmin
    include BuildsDatastoreCore
    extend self
    extend CommonSpecHelpers

    def build_admin(datastore_core: nil, **options, &customize_datastore_config)
      Admin.new(datastore_core: datastore_core || build_datastore_core(for_context: :admin, **options, &customize_datastore_config))
    end
  end

  RSpec.configure do |c|
    c.include BuildsAdmin, :builds_admin
  end
end
