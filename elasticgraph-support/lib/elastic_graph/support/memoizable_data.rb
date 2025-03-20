# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "stringio"

module ElasticGraph
  module Support
    # `::Data.define` in Ruby 3.2+ is *very* handy for defining immutable value objects. However, one annoying
    # aspect: instances are frozen, which gets in the way of defining a memoized method (e.g. a method that
    # caches the result of an expensive computation). While memoization is not always safe (e.g. if you rely
    # on an impure side-effect...) it's safe if what you're memoizing is a pure function of the immutable state
    # of the value object. We rely on that very heavily in ElasticGraph (and used it with a prior "value objects"
    # library we use before upgrading to Ruby 3.2).
    #
    # This abstraction aims to behave just like `::Data.define`, but with the added ability to define memoized methods.
    # It makes this possible by combining `::Data.define` with `SimpleDelegator`: that defines a data class, but then
    # wraps instances of it in a `SimpleDelegator` instance which is _not_ frozen. The memoized methods can then be
    # defined on the wrapper.
    #
    # Note: getting this code to typecheck with steep is quite difficult, so we're just skipping it.
    __skip__ =
      module MemoizableData
        # Defines a data class using the provided attributes.
        #
        # A block can be provided in order to define custom methods (including memoized methods!) or to override
        # `initialize` in order to provide field defaults.
        def self.define(*attributes, &block)
          data_class = ::Data.define(*attributes)

          DelegateClass(data_class) do
            # Store a reference to our wrapped data class so we can use it in `ClassMethods` below.
            const_set(:DATA_CLASS, data_class)

            # Define default version of` after_initialize`. This is a hook that a user may override.
            # standard:disable Lint/NestedMethodDefinition
            private def after_initialize
            end
            # standard:enable Lint/NestedMethodDefinition

            # If a block is provided, we evaluate it so that it can define memoized methods.
            if block
              original_initialize = instance_method(:initialize)
              module_eval(&block)

              # It's useful for the caller to be define `initialize` in order to provide field defaults, as
              # shown in the `Data` docs:
              #
              # https://rubyapi.org/3.2/o/data
              #
              # However, to make that work, we need the `initialize` definition to be included in the data class,
              # rather than in our `DelegateClass` wrapper.
              #
              # Here we detect when the block defines an `initialize` method.
              if instance_method(:initialize) != original_initialize
                # To mix the `initialize` override into the data class, we re-evaluate the block in a new module here.
                # The module ignores all method definitions except `initialize`.
                init_override_module = ::Module.new do
                  # We want to ignore all methods except the `initialize` method so that this module only contains `initialize`.
                  def self.method_added(method_name)
                    remove_method(method_name) unless method_name == :initialize
                  end

                  module_eval(&block)
                end

                data_class.include(init_override_module)
              end
            end

            # `DelegateClass` objects are mutable via the `__setobj__` method. We don't want to allow mutation, so we undefine it here.
            undef_method :__setobj__

            prepend MemoizableData::InstanceMethods
            extend MemoizableData::ClassMethods
          end
        end

        module InstanceMethods
          # SimpleDelegator#== automatically defines `==` so that it unwraps the wrapped type and calls `==` on it.
          # However, the wrapped type doesn't automatically define `==` when given an equivalent wrapped instance.
          #
          # For `==` to work correctly we need to unwrap _both_ sides before delegating, which this takes care of.
          def ==(other)
            case other
            when MemoizableData::InstanceMethods
              __getobj__ == other.__getobj__
            else
              super
            end
          end

          # `with` is a standard `Data` API that returns a new instance with the specified fields updated.
          #
          # Since `DelegateClass` delegates all methods to the wrapped object, `with` will return an instance of the
          # data class and not our wrapper. To overcome that, we redefine it here so that the new instance is re-wrapped.
          def with(**updates)
            # Note: we intentionally do _not_ `super` to the `Date#with` method here, because in Ruby 3.2 it has a bug that
            # impacts us: `with` does not call `initialize` as it should. Some of our value classes (based on the old `values` gem)
            # depend on this behavior, so here we work around it by delegating to `new` after merging the attributes.
            #
            # This bug is fixed in Ruby 3.3 so we should be able to revert back to an implementation that delegates with `super`
            # after we are on Ruby 3.3. For more info, see:
            # - https://bugs.ruby-lang.org/issues/19259
            # - https://github.com/ruby/ruby/pull/7031
            self.class.new(**to_h.merge(updates))
          end
        end

        module ClassMethods
          # `new` on a `SimpleDelegator` class accepts an instance of the wrapped type to wrap. `MemoizableData` is intended to
          # hide the wrapping we're doing here, so here we want `new` to accept the direct arguments that `new` on the `Data` class
          # would accept. Here we instantiate the data class and the wrap it.
          def new(*args, **kwargs)
            data_instance = self::DATA_CLASS.new(*args, **kwargs)

            # Here we re-implement `new` (rather than using `super`) because `initialize` may be overridden.
            allocate.instance_eval do
              # Match `__setobj__` behavior: https://github.com/ruby/ruby/blob/v3_2_2/lib/delegate.rb#L411
              @delegate_dc_obj = data_instance
              after_initialize
              self
            end
          end

          # `SimpleDelegator` delegates instance methods but not class methods. This is a standard `Data` class method
          # that is worth delegating.
          def members
            self::DATA_CLASS.members
          end

          def method_added(method_name)
            return unless method_name == :initialize

            raise "`#{name}` overrides `initialize` in a subclass of `#{MemoizableData.name}`, but that can break things. Instead:\n\n" \
              "  1) If you want to coerce field values or provide default field values, define `initialize` in a block passed to `#{MemoizableData.name}.define`.\n" \
              "  2) If you want to perform some post-initialization setup, define an `after_initialize` method."
          end
        end
      end
  end
end
