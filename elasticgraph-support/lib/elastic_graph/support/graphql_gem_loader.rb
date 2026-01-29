# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # Helper module to load the graphql gem and optionally graphql-c_parser for better performance.
    # Prints a yellow warning to stderr when c_parser is unavailable (except on JRuby where C extensions don't work).
    #
    # @private
    module GraphQLGemLoader
      # ANSI escape code for yellow text
      YELLOW = "\e[33m"
      RESET = "\e[0m"

      @warning_printed = false # : bool

      # Loads the graphql gem and attempts to load graphql/c_parser.
      # If c_parser is unavailable, prints a warning once (unless on JRuby).
      def self.load
        require "graphql"

        begin
          require "graphql/c_parser"
        rescue LoadError
          print_warning_once
        end
      end

      def self.print_warning_once
        return if @warning_printed || RUBY_ENGINE == "jruby"

        @warning_printed = true
        warn "#{YELLOW}[ElasticGraph] For better performance, add `graphql-c_parser` to your Gemfile. See: https://graphql-ruby.org/language_tools/c_parser.html#{RESET}"
      end

      # Resets warning state; only intended for use in tests.
      def self.reset_warning_state!
        @warning_printed = false
      end

      private_class_method :print_warning_once, :reset_warning_state!
    end
  end
end
