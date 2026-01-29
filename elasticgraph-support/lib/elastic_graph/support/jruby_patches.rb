# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Central location for JRuby workarounds.
# Each patch should reference the upstream fix and specify when it can be removed.

if ::Gem::Version.new(JRUBY_VERSION) < ::Gem::Version.new("10.0.4.0")
  module ElasticGraph
    module Support
      # @private
      module JRubyPatches
        # Bug 1: `Data.new(*args, **kwargs)` with empty kwargs breaks positional-to-keyword
        # argument conversion. We patch every `Data.define`-created class so that `*args` and
        # `**kwargs` are never forwarded together.
        # Note: uses `alias_method` instead of `prepend`+`super` because `Factory.prevent_non_factory_instantiation_of`
        # calls `undef_method :new` on some Data classes, which blocks `super` from finding the original `.new`.
        # Fixed upstream: https://github.com/jruby/jruby/pull/9215,
        #                 https://github.com/jruby/jruby/pull/9225
        # TODO: remove once we no longer support JRuby < 10.0.4.0.
        # @private
        module DataDefineNewPatch
          def define(*members, &block)
            klass = super
            klass.singleton_class.class_eval do
              alias_method :__original_new, :new
              def new(*args, **kwargs)
                if kwargs.empty?
                  __original_new(*args)
                elsif args.empty?
                  __original_new(**kwargs)
                else
                  raise ::ArgumentError, "`Data.new` does not accept mixed positional and keyword arguments"
                end
              end
            end
            klass
          end
        end

        ::Data.singleton_class.prepend(DataDefineNewPatch)
      end
    end
  end

  # Bug 2: When a module overrides `initialize` with `super(**reordered_hash)` inside a
  # `Data.define` block and the class is subclassed, `to_h`/`deconstruct` return values by
  # position rather than name. Accessors are correct, so we derive values from them instead.
  # Reported upstream: https://github.com/jruby/jruby/issues/9241
  # TODO: remove once we no longer support JRuby < 10.0.4.0.
  ::Data.class_exec do
    def to_h(&block)
      result = self.class.members.to_h { |m| [m, public_send(m)] }
      block ? result.to_h(&block) : result
    end

    def deconstruct
      self.class.members.map { |m| public_send(m) }
    end

    def deconstruct_keys(keys)
      keys ? to_h.slice(*keys) : to_h
    end
  end
end
