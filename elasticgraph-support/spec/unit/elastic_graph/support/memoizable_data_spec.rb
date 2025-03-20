# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module Support
    RSpec.describe MemoizableData do
      specify "`::Data.define` does not allow memoized methods to be defined" do
        # If this restriction is ever relaxed in a future version of Ruby, we should remove `MemoizableData`
        # and just use `Data` directly!
        unmemoizable_class = ::Data.define(:x, :y) do
          def sum
            @sum ||= x + y
          end
        end

        expect {
          unmemoizable_class.new(1, 2).sum
        }.to raise_error ::FrozenError
      end

      shared_examples_for MemoizableData do
        let(:memoizable_class) do
          define(:x, :y) do
            def sum
              @sum ||= x + y
            end
          end
        end

        it "allows us to define memoized methods on value objects to cache expensive, but pure, derived computations" do
          expect(memoizable_class.new(1, 2).sum).to eq(3)
        end

        specify "the memoization has no impact on the equality semantics of the class" do
          m1 = memoizable_class.new(1, 2)
          m2 = memoizable_class.new(1, 2)
          m2.sum # so that the memoized state changes

          expect(m1 == m2).to be true
          expect(m1.eql?(m2)).to be true
          expect(m1.equal?(m2)).to be false
          expect(m1.hash).to eq(m2.hash)

          # Swap the operands to confirm the same semantics hold...
          expect(m2 == m1).to be true
          expect(m2.eql?(m1)).to be true
          expect(m2.hash).to eq(m1.hash)
          expect(m2.equal?(m1)).to be false

          # instantiate an instance that is not equal...
          m3 = memoizable_class.new(1, 3)

          expect(m2 == m3).to be false
          expect(m2.eql?(m3)).to be false
          expect(m2.eql?(m3)).to be false
          expect(m2.hash).not_to eq(m3.hash)

          # Swap the operands to confirm the same semantics hold...
          expect(m3 == m2).to be false
          expect(m3.eql?(m2)).to be false
          expect(m3.eql?(m2)).to be false
          expect(m3.hash).not_to eq(m2.hash)

          # Verify our ability to compare against objects that aren't of the same type...
          expect(m1 == 5).to be false
        end

        it "supports creating new instances using `#with`" do
          m1 = memoizable_class.new(1, 2)

          expect(m1.sum).to eq(3)

          m2 = m1.with(y: 3)
          expect(m2).to be_a(memoizable_class)
          expect(m2.y).to eq(3)
          expect(m2.sum).to eq(4)

          expect(m1.sum).to eq(3)
          expect(m2).not_to eq(m1)
        end

        it "returns the outer type from `#itself` rather than the inner wrapped type" do
          m1 = memoizable_class.new(1, 2)

          expect(m1.itself).to be_a(memoizable_class)
          expect(m1.sum).to eq(3)
        end

        it "can be instantiated with keyword or positional args" do
          m1 = memoizable_class.new(1, 2)
          m2 = memoizable_class.new(x: 1, y: 2)

          expect(m1).to eq(m2)
        end

        it "exposes the same `members` as a data class" do
          expect(memoizable_class.members).to eq [:x, :y]

          m1 = memoizable_class.new(1, 2)
          expect(m1.members).to eq [:x, :y]
        end

        it "inspects nicely" do
          m1 = memoizable_class.new(1, 2)

          expect(m1.to_s).to eq "#<data x=1, y=2>"
          expect(m1.inspect).to eq "#<data x=1, y=2>"
        end

        it "does not allow mutation via `__setobj__` (which `DelegateClass` usually provides)" do
          example_delegate_class = DelegateClass(::String)
          expect(example_delegate_class.new(1)).to respond_to(:__setobj__)

          m1 = memoizable_class.new(1, 2)
          expect(m1).not_to respond_to(:__setobj__)
        end

        it "supports an `after_initialize` hook" do
          klass = define(:tags) do
            private

            def after_initialize
              tags.freeze
            end
          end

          instance = klass.new(tags: ["a", "b"])
          expect(instance.tags).to be_frozen

          instance = instance.with(tags: ["c"])
          expect(instance.tags).to be_frozen
        end
      end

      context "with methods defined via a passed block" do
        def define(...)
          MemoizableData.define(...)
        end

        include_examples MemoizableData

        it "allows `initialize` to be overridden in the same way as on a data class" do
          measure = define(:amount, :unit) do
            def initialize(amount:, unit: "unknown")
              super(amount: Float(amount), unit:)
            end
          end

          a_mile = measure.new("5280", "ft")
          expect(a_mile.amount).to eq(5280)
          expect(a_mile.unit).to eq("ft")

          ten = measure.new(10)
          expect(ten.amount).to eq(10)
          expect(ten.unit).to eq("unknown")
        end

        it "adds the defined methods only to the `MemoizableData`, not to the wrapped data class" do
          measure = define(:amount, :unit) do
            def initialize(amount:, unit: "unknown")
              # :nocov:
              super(amount: Float(amount), unit:)
              # :nocov:
            end

            def description
              # :nocov:
              @description ||= "#{amount} #{unit}"
              # :nocov:
            end
          end

          expect(measure.method_defined?(:description)).to be true
          expect(measure::DATA_CLASS.method_defined?(:description)).to be false
        end

        it "allows `initialize` to be used for coercion, using it when `#with` is called" do
          klass = define(:tags) do
            def initialize(tags:)
              super(tags: tags.to_set)
            end
          end

          k1 = klass.new(tags: ["a", "b"])
          expect(k1.tags).to be_a(::Set)

          k2 = k1.with(tags: ["c"])
          expect(k2.tags).to be_a(::Set)
        end
      end

      context "with methods defined on a subclass" do
        def define(*attrs, &method_def_block)
          ::Class.new(MemoizableData.define(*attrs), &method_def_block)
        end

        include_examples MemoizableData

        it "raises an error if you attempt to override `initialize` in the subclass since it breaks things" do
          expect {
            define(:amount, :unit) do
              def self.name
                "MyData"
              end

              def initialize(amount:, unit: "unknown")
                # :nocov:
                super(amount: Float(amount), unit:)
                # :nocov:
              end
            end
          }.to raise_error a_string_including("`MyData` overrides `initialize` in a subclass of `ElasticGraph::Support::MemoizableData`, but that can break things.")
        end
      end

      specify "`respond_to?` works as expected in a mixin with a method defined on a subclass" do
        # Demonstrate that this works on `::Data`
        expect(define_subclass_with_can_resolve_mixin(::Data).new(1, 2).can_resolve?(:sum)).to be true
        # It should also work with `MemoizableData`.
        expect(define_subclass_with_can_resolve_mixin(MemoizableData).new(1, 2).can_resolve?(:sum)).to be true
      end

      def define_subclass_with_can_resolve_mixin(data_class)
        my_module = ::Module.new do
          def can_resolve?(field)
            respond_to?(field)
          end
        end

        klass = data_class.define(:x, :y) do
          include my_module
        end

        ::Class.new(klass) do
          def sum
            # :nocov:
            x + y
            # :nocov:
          end
        end
      end
    end
  end
end
