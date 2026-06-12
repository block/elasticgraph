# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        module FieldType
          # Provides value-equality semantics for the JSON-schema-aware field type wrappers that delegate
          # to a wrapped core field type without adding any state of their own (`Scalar`, `Enum`, `Union`).
          #
          # `DelegateClass` defines `==` so that it unwraps only the *left* operand before comparing, which
          # means `wrapper == equivalent_wrapper` compares the wrapped object against the right-hand
          # *wrapper* (rather than against its wrapped object) and is therefore never equal--even though
          # `hash` delegates to the wrapped object and reports them equal. That inconsistency breaks the
          # `eql?`/`hash` contract and causes `Set`/`Hash`/`uniq` de-duplication to treat equivalent
          # wrappers as distinct. Here we unwrap both sides so two wrappers around equal objects compare
          # equal, keeping `==`/`eql?`/`hash` consistent. (`FieldType::Object` solves the same problem with
          # its own implementation because it carries additional JSON schema state in its equality.)
          #
          # @private
          module ValueSemantics
            # @param other [Object] the object to compare against
            # @return [Boolean] true when `other` wraps an equal field type (or is the wrapped field type itself)
            def ==(other)
              case other
              when ValueSemantics
                __getobj__ == other.__getobj__
              else
                super
              end
            end

            def eql?(other)
              self == other
            end

            # @return [Integer] a hash code derived from the wrapped field type
            def hash
              __getobj__.hash
            end
          end
        end
      end
    end
  end
end
