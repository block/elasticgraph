# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

::RSpec::Matchers.define :have_readable_to_s_and_inspect_output do
  max_length = 150

  # :nocov: -- the logic in these blocks isn't covered on every test run (e.g. because we don't have failures each test run)
  chain :including do |*inclusions|
    @inclusions = inclusions
  end

  chain :and_excluding do |*exclusions|
    @exclusions = exclusions
  end

  match do |object|
    to_s = object.to_s
    inspect = object.inspect

    @problems = []

    @problems << "`inspect` and `to_s` did not have the same output" unless to_s == inspect
    @problems << "the output is too long (#{to_s.length} vs target max of #{max_length})" if to_s.length > max_length
    expected_start = "#<#{object.class.name}"
    @problems << "Does not start with `#{expected_start}`" unless to_s.start_with?(expected_start)
    @problems << "Does not end with `>`" unless to_s.end_with?(">")

    if @inclusions
      @problems << "Does not include #{@inclusions.map { |s| "`#{s}`" }.join(", ")}" unless @inclusions.all? { |s| to_s.include?(s) }
    end

    if @exclusions
      @problems << "Does not exclude #{@exclusions.map { |s| "`#{s}`" }.join(", ")}" unless @exclusions.none? { |s| to_s.include?(s) }
    end

    @problems.empty?
  end

  failure_message do |object|
    <<~EOS
      expected `#{object.class.name}` instance to #{description}, but had #{@problems.size} problem(s):

      #{@problems.map.with_index { |p, i| "#{i + 1}) #{p}" }.join("\n")}

      `to_s`: #{truncate(object.to_s)}
      `inspect`: #{truncate(object.inspect)}
    EOS
  end

  description do
    super().sub(" to s ", " `#to_s` ").sub(" inspect ", " `#inspect` ")
  end

  define_method :truncate do |str|
    if str.length > 3 * max_length
      "#{str[0, max_length * 3]}..."
    else
      str
    end
  end
  # :nocov:
end
