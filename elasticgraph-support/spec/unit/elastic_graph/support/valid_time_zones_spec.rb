# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/valid_time_zones"

module ElasticGraph
  module Support
    RSpec.describe "VALID_TIME_ZONES" do
      it "is up-to-date with the list of time zones available on the JVM (since that's the list that Elasticsearch/OpenSearch use)" do
        expected_time_zones_file = `#{SPEC_ROOT}/../script/dump_time_zones --print`.lines.reject do |line|
          # "America/Coyhaique" is a new TimeZone added to the 2025b tzdata database^[1]. In July 2025, the JDKs on the standard
          # GitHub actions workers was updated to this new database and this test started failing (because `valid_time_zones.rb`
          # lacks it). We want to hold off on adding it until it's widely supported by all versions of Elasticsearch/OpenSearch
          # we build against, so for now we reject it here, allowing the test to pass.
          #
          # Once it is widely supported, we can remove this `.reject` block.
          #
          # [^1]: https://lists.iana.org/hyperkitty/list/tz-announce%40iana.org/thread/6JVHNHLB6I2WAYTQ75L6KEPEQHFXAJK3/
          line.include?("America/Coyhaique")
        end.join

        actual_time_zones_file = ::File.read(::File.join(SPEC_ROOT, "..", "lib", "elastic_graph", "support", "valid_time_zones.rb"))

        # Verify the file is up to date. If out of date, run `script/dump_time_zones` to fix it.
        expect(actual_time_zones_file).to eq(expected_time_zones_file)
      end
    end
  end
end
