# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Central location for JRuby workarounds in the schema_definition gem.
# Each patch should reference the upstream fix and specify when it can be removed.

module ElasticGraph
  module SchemaDefinition
    # @private
    module JRubyPatches
      # Bug: `Thread::Backtrace::Location#absolute_path` returns a relative path (same as `#path`)
      # when the source file was loaded via `load` with a bare relative path (e.g. `load "schema.rb"`).
      # On MRI, `absolute_path` correctly resolves to the full absolute path in this case.
      # Workaround: override `absolute_path` to expand relative paths.
      # Reported upstream: https://github.com/jruby/jruby/issues/9245
      # TODO: remove once JRuby fixes this upstream.
      # @private
      module BacktraceLocationAbsolutePathPatch
        def absolute_path
          result = super
          return result if result.nil? || result.start_with?("/")
          ::File.expand_path(result)
        end
      end

      ::Thread::Backtrace::Location.class_exec do
        prepend BacktraceLocationAbsolutePathPatch
      end
    end
  end
end
