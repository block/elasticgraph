# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Dynamic mixin that provides readable output from `#to_s` and `#inspect`. The default
      # output Ruby prints for these methods is quite unwieldy for all our schema definition
      # types, because we have a large interconnected object graph and `Struct` classes print
      # all their state. In fact, before implementing this, we observed output of more than
      # 5 million characters long!
      #
      # To use this module include a new instance of it:
      #
      #   include HasReadableToSAndInspect.new
      #
      # Optionally, provide a block that, given an instance of the class, returns a string description for
      # inclusion in the output:
      #
      #   include HasReadableToSAndInspect.new { |obj| obj.name }
      #
      # @private
      class HasReadableToSAndInspect < ::Module
        def initialize
          if block_given?
            define_method :to_s do
              "#<#{self.class.name} #{yield self}>"
            end
          else
            # When no block is given, we just want to use the stock `Object#to_s`, which renders the memory address.
            define_method :to_s do
              ::Object.instance_method(:to_s).bind_call(self)
            end
          end

          alias_method :inspect, :to_s
        end
      end
    end
  end
end
