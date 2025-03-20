# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/datastore_core/index_definition/index"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      # Represents a concrete index for specific time range, derived from a RolloverIndexTemplate.
      class RolloverIndex < DelegateClass(Index)
        # @dynamic time_set
        attr_reader :time_set

        def initialize(index, time_set)
          super(index)
          @time_set = time_set
        end

        # We need to override `==` so that two `RolloverIndex` objects that wrap the same `Index` object are
        # considered equal. Oddly enough, the `DelegateClass` implementation of `==` returns `true` if `other`
        # is the wrapped object, but not if it's another instance of the same `DelegateClass` wrapping the same
        # instance.
        #
        # https://github.com/ruby/ruby/blob/v3_0_3/lib/delegate.rb#L156-L159
        #
        # We need this because we want two `RolloverIndex` instances that wrap the same
        # underlying `Index` instance to be considered equal (something a test relies upon,
        # but also generally useful and expected).
        def ==(other)
          if RolloverIndex === other
            __getobj__ == other.__getobj__ && time_set == other.time_set
          else
            # :nocov: -- this method isn't explicitly covered by tests (not worth writing a test just to cover this line).
            super
            # :nocov:
          end
        end
        alias_method :eql?, :==
      end
    end
  end
end
