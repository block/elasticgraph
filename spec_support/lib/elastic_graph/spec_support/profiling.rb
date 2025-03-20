# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# :nocov: -- when running with the parallel spec runner we patch this to disable it, so things here are uncovered.
module ElasticGraphProfiler
  def self.results
    @results ||= Hash.new { |h, k| h[k] = [] }
  end

  def self.record(id, skip_frames: 1)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return_value = yield
    stop = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    record_raw(
      id,
      stop - start,
      # Record some caller frames for use later on. We skip the first few frames
      # (to skip the profiling logic) as we really want to see the caller from the
      # spec file, and 50 frames should be good enough to be able to identify the callsite.
      # We don't get all caller frames because that can be expensive.
      caller_frames: caller(skip_frames, 50)
    )

    return_value
  end

  def self.record_raw(id, duration, caller_frames: [])
    results[id] << {
      duration: duration,
      example: RSpec.current_example,
      # Record some caller frames for use later on. We skip the first few frames
      # (to skip the profiling logic) as we really want to see the caller from the
      # spec file, and 50 frames should be good enough to be able to identify the callsite.
      # We don't get all caller frames because that can be expensive.
      caller_frames: caller_frames
    }
  end

  def self.report_results
    computed_results = results.map do |id, results_for_id|
      durations = results_for_id.map { |h| h.fetch(:duration) }
      total = durations.sum
      count = durations.count
      max_result = results_for_id.max_by { |h| h.fetch(:duration) }

      # Identify where in the spec this method was called--preferrably
      # from a spec file itself, but if we can't find it there, a support
      # file in the spec directory is also OK.
      callsite = max_result.fetch(:caller_frames).find do |line|
        line.include?("/spec/") && line =~ /_spec\.rb:\d+/
      end || max_result.fetch(:caller_frames).find do |line|
        line.include?("/spec/")
      end || "(can't identify callsite)"

      # shorten it to a relative path instead of an absolute one.
      callsite = callsite.sub(/.*\/spec\//, "./spec/")

      {
        id: id,
        count: count,
        max: max_result.fetch(:duration).round(3),
        total: total.round(3),
        avg: (total / count).round(3),
        example: max_result.fetch(:example),
        callsite: callsite
      }
    end

    top_results = computed_results
      .sort_by { |result| result.fetch(:total) }
      .last(6)
      .reverse

    puts
    puts "=" * 120
    puts "Top #{top_results.size} profiling results:"

    top_results.each_with_index do |result, index|
      puts "#{index + 1}) `#{result[:id]}`: #{result[:count]} calls in #{result[:total]} sec (#{result[:avg]} sec avg)"
      puts "Max time: #{result.fetch(:max)} sec for `#{result[:example]&.id || "(outside of an example)"}` from `#{result[:callsite]}`"
      puts "-" * 120
    end
    puts "=" * 120
  end
end

RSpec.configure do |c|
  c.after(:suite) do
    ElasticGraphProfiler.report_results if c.profile_examples?
  end
end
# :nocov:
