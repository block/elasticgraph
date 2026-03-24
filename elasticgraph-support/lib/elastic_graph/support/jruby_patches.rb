# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Central location for JRuby workarounds in the support gem.
#
# Bug 1 (Data.new splat forwarding, jruby/jruby#9215, #9225): fixed in JRuby 10.0.4.0.
# Bug 2 (Data#to_h/deconstruct on subclasses, jruby/jruby#9241): fixed in JRuby 10.0.4.0.
#
# Both patches have been removed. If JRuby regressions surface, the git history
# (prior to this commit) contains the full implementations.
