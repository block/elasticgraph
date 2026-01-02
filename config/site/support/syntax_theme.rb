# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "rouge"

module ElasticGraph
  # A custom Rouge theme based on Tulip but without the purple background
  # Tulip appears to provide the best looking syntax highlighting theme of all the built-in rouge themes,
  # apart from the purple background..
  class SyntaxTheme < Rouge::Themes::Tulip
    name "elasticgraph"

    # Override just the background color from the parent theme
    style Text, {}  # Empty style to remove background color
    style Generic::Output, {}  # Empty style to remove background color
  end
end
