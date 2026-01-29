# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Central location for JRuby workarounds in the graphql gem.
# Each patch should reference the upstream fix and specify when it can be removed.

# Bug: graphql-ruby's `Dataloader#with` has two branches:
#   - MRI Ruby 3+: `def with(source_class, *batch_args, **batch_kwargs)` -- properly separates kwargs
#   - Non-MRI or Ruby < 3: `def with(source_class, *batch_args)` -- collapses kwargs into a Hash in batch_args
#
# JRuby 10 targets Ruby 3.4 compatibility and handles **kwargs correctly, but
# graphql-ruby excludes all non-MRI engines due to a TruffleRuby issue.
# This causes `Source.new` to receive a positional Hash instead of keyword args,
# breaking any Source subclass that uses keyword-only parameters in `initialize`.
#
# Reported upstream: https://github.com/rmosolgo/graphql-ruby/issues/5541
# TODO: remove once graphql-ruby supports JRuby in the kwargs branch.
::GraphQL::Dataloader.class_exec do
  def with(source_class, *batch_args, **batch_kwargs)
    batch_key = source_class.batch_key_for(*batch_args, **batch_kwargs)
    @source_cache[source_class][batch_key] ||= begin
      source = source_class.new(*batch_args, **batch_kwargs)
      source.setup(self)
      source
    end
  end
end
