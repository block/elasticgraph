# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Extensions
    module ValidModule
      def self.class_method(a, b)
      end

      def instance_method1
      end

      def instance_method2(foo:)
      end
    end
  end
end
