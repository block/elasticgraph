# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Extensions
    NotAClassOrModule = Object.new

    def NotAClassOrModule.class_method(a, b)
    end
  end
end
