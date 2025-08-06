# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/monotonic_clock"

module ElasticGraph
  module Support
    RSpec.describe MonotonicClock do
      let(:clock) { MonotonicClock.new }

      it "reports a monotonically increasing time value suitable for tracking durations and deadlines without worrying about leap seconds, etc" do
        expect {
          sleep(0.002) # sleep for 2 ms; ensuring it's > 1 ms so the monotonic clock value is guaranteed to change
        }.to change { clock.now_in_ms }.by(a_value_between(
          1, # maybe it's possible with rounding for the sleep to be *slightly* less than 2 ms and this only increase by 1
          1000 # give plenty of time (up to a second) for GC pauses, etc so our test doesn't flicker
        ))
      end
    end
  end
end
