# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This example adapter is shared by multiple gem suites (e.g. `elasticgraph-schema_definition`
# and `elasticgraph-json_ingestion`). It must live in `spec_support` (rather than being
# duplicated under each gem's `spec/support`) so that every suite loads it from the same
# require path: the extension loader raises if the same extension is loaded from two
# different paths within one process, as can happen when one worker runs multiple suites.
class ExampleScalarCoercionAdapter
  def self.coerce_input(value, ctx)
  end

  def self.coerce_result(value, ctx)
  end
end
