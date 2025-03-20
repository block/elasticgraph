# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/spec_support/factories/teams"
require "elastic_graph/spec_support/factories/widgets"
require "elastic_graph/support/hash_util"

RSpec.shared_context "factories" do
  # we use `prepend_before` so this runs before other `before` hooks.
  prepend_before do |ex|
    # Make faker usage deterministic, based on the `full_description` string of the
    # RSpec example. `String#sum` is being used purely for speed, as we do not
    # need a particularly even distribution in random number seeds.
    Faker::Config.random = Random.new(ex.full_description.sum)
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
