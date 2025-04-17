# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# On CI, we do want to be able to avoid loading VCR (we care more about accuracy than speed), so
# we support using `NO_VCR=1 rspec` to skip VCR.
# :nocov: -- we avoid loading/using VCR when these ENV vars are set
return if ENV["NO_VCR"]

require "vcr"
require "rspec/retry"
require "method_source" # needed by `aggregate_failures_meta_value_for` method below.

module VCRSupport
  extend self

  def aggregate_failures_meta_value_for(meta)
    !(meta[:uses_datastore] && meta[:block]&.source&.include?("raise_error"))
  end

  def name_for(metadata)
    description = metadata[:description]

    example_group = metadata.fetch(:example_group) do
      metadata.fetch(:parent_example_group) do
        return description
      end
    end

    [name_for(example_group), description].join("/")
  end

  # Used to match against `VCR::Errors::UnhandledHTTPRequestError` exceptions
  # and any exceptions that are caused by that type of exception (as indicated
  # by its presence as the `cause` or it being mentioned in the `message).
  #
  # This is needed to deal with VCR errors that happen in blocks that we apply
  # `raise_error` matchers too, since RSpec rescues the error and transforms it to
  # an RSpec failure instead of a VCR error.
  module ExceptionCausedByVCRUnhandledHTTPRequestError
    def self.===(exception)
      if VCR::Errors::UnhandledHTTPRequestError === exception ||
          exception.message.include?(VCR::Errors::UnhandledHTTPRequestError.name)
        return true
      end

      return self === exception.cause if exception.cause
      false
    end
  end
end

VCR.configure do |config|
  # We use a directory in `tmp` for cassettes. We do not want them to ever be committed to
  # source control. We are using VCR just to speed things up (as a smart cache) and do
  # not want any tests to rely on VCR to pass.
  config.cassette_library_dir = "#{ElasticGraph::CommonSpecHelpers::REPO_ROOT}/tmp/vcr_cassettes"
  config.hook_into :faraday # the datastore client is built on faraday

  # Do not record when the example fails. In the past we've occasionally had
  # confusing situations where we've screwed up our running datastore node
  # (e.g. by deleting its working directory while its running), and when that
  # happened, VCR recorded the failed response returned by the datastore. After
  # restarting the datastore to fix the issue, specs continued to fail with the
  # same failure because VCR recorded the temporary response error, and is playing
  # it back on a later test run. This led us to scratch our heads and waste time.
  #
  # To avoid this situation, we want to entirely avoid recording when an example
  # fails, as there is no significant benefit to doing so. Note that this line
  # is only part of what makes this work; we also have to call `cassette.run_failed!`
  # in our `VCR.use_cassette` block below, because RSpec handles exceptions (so it can
  # print the failures, etc), which means that a failure in an example isn't propagated
  # to VCR unless we manually call `cassette.run_failed!`.
  config.default_cassette_options[:record_on_error] = false
end

RSpec.configure do |config|
  console_codes = RSpec::Core::Formatters::ConsoleCodes

  # Here we hook up rspec/retry for examples that use VCR. During playback,
  # when VCR encounters a request for which it does not have a recorded response,
  # a VCR::Errors::UnhandledHTTPRequestError exception will get raised. When this
  # happens, we delete the cassette and try again (which will automatically re-record).
  config.retry_callback = ->(ex) {
    file = ex.metadata.fetch(:cassette_file)
    puts console_codes.wrap(
      "Got a VCR unhandled request exception. Deleting the cassette (#{file}) and rerunning the example.",
      :yellow
    )

    # Work around a bug in rspec-retry. It clears state stored using `let`, but not any
    # other state. Unfortunately, that allows state from the first run attempt to leak
    # into the retry, which leads to bugs on retry. The simple (but hacky) fix is to
    # remove all instance variables set in the scope of the example before re-running,
    # with the exception of `@__memoized`, which RSpec sets eagerly (not lazily), and
    # which rspec-retry handles for us. All other instance variables are set while the
    # example is running, and removing the variable here will allow it to re-evaluate
    # to a new value as needed when the example re-runs.
    ex.example_group_instance.instance_eval do
      instance_variables.each do |ivar|
        next if ivar == :@__memoized
        remove_instance_variable(ivar)
      end
    end

    File.delete(file)

    # Examples tagged with `:in_temp_dir` get run in a temporary directory using an `around` hook.
    # However, `run_with_retry` does not re-run the `around` hook for some reason (seems like a bug).
    # That can cause a problem because the tmp dir won't be empty as expected when the example is
    # retried. We work around that here by deleting all the files in the current temp dir in this case.
    FileUtils.rm_rf(".") if ex.metadata[:in_temp_dir] && Dir.pwd.include?(Dir.tmpdir)
  }

  exceptions_to_retry = [VCRSupport::ExceptionCausedByVCRUnhandledHTTPRequestError]

  config.around(:example, :vcr) do |ex|
    ex.run_with_retry(retry: 2, exceptions_to_retry: exceptions_to_retry)
  end

  # Note:
  #
  #   - This uses an `around` hook instead of a `before`/`after` hook (or
  #     VCR's `configure_rspec_metadata!`) because some datastore HTTP requests
  #     are made in a `before` hook (such as clearing the indices) and we must wrap
  #     all datastore requests with VCR. Around hooks wrap before/after hooks.
  #   - This must be defined after the `around` hook with `ex.run_with_retry` defined
  #     above, because it is important the `run_with_retry` wraps the VCR cassette, so
  #     that the cassette is ejected, then re-inserted for the next attempt, rather
  #     than wrapping multiple attempts.
  config.around(:example, :vcr, no_vcr: false) do |ex|
    vcr_options = ex.metadata[:vcr].is_a?(Hash) ? ex.metadata[:vcr] : {}
    VCR.use_cassette(VCRSupport.name_for(ex.metadata), **vcr_options) do |cassette|
      # store the cassette file for use in our retry callback.
      ex.metadata[:cassette_file] = cassette.file
      ex.run

      # Notify the cassette if we got an error, so it honors `record_on_error: false`.
      cassette.run_failed! if ex.exception && exceptions_to_retry.none? { |ex_class| ex_class === ex.exception }
    end
  end
end
# :nocov:
