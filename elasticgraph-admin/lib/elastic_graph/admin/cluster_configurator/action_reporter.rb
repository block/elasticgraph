# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Admin
    class ClusterConfigurator
      class ActionReporter
        def initialize(output)
          @output = output
        end

        def report_action(message)
          @output.puts "#{message.chomp}\n#{"=" * 80}\n"
        end
      end
    end
  end
end
