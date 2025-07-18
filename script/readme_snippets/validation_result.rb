# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Represents the result of validating a README snippet
ValidationResult = ::Data.define(:status, :emoji, :output) do
  def success?
    status != :failed
  end

  def self.passed(output = "")
    new(status: :passed, emoji: "✅", output: output)
  end

  def self.skipped(output = "")
    new(status: :skipped, emoji: "⏭️", output: output)
  end

  def self.unvalidated(output = "")
    new(status: :unvalidated, emoji: "📝", output: output)
  end

  def self.failed(output = "")
    new(status: :failed, emoji: "❌", output: output)
  end
end
