# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # Adapts an ElasticGraph GraphQL endpoint to run as a [Rack](https://github.com/rack/rack) application.
  # This allows an ElasticGraph GraphQL endpoint to run inside any [Rack-compatible web
  # framework](https://github.com/rack/rack#supported-web-frameworks), including [Ruby on Rails](https://rubyonrails.org/),
  # or as a stand-alone application.
  module Rack
  end
end
