# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Central location for JRuby workarounds.
# Each patch should reference the upstream fix and specify when it can be removed.

# When a module overrides `initialize` with `super(**reordered_hash)` inside a
# `Data.define` block and the class is subclassed, `to_h`/`deconstruct` return values by
# position rather than name. Accessors are correct, so we derive values from them instead.
# Reported upstream: https://github.com/jruby/jruby/issues/9241
# Note: the upstream fix in JRuby 10.0.4.0 is incomplete (the subclass case is still broken).
# TODO: remove once JRuby fully fixes https://github.com/jruby/jruby/issues/9241.
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
