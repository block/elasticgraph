# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/hash_util"
require "elastic_graph/spec_support/in_sub_process"
require "json"
require "logger"
require "tmpdir"
require "yaml"

RSpec.shared_context "lambda function" do |config_overrides_in_yaml: {}|
  include_context "in_sub_process"

  around do |ex|
    ::Dir.mktmpdir do |dir|
      @tmp_dir = dir
      @config_dir = dir
      with_lambda_env_vars(&ex)
    end
  end

  let(:base_config) { ::YAML.safe_load_file(ElasticGraph::CommonSpecHelpers.test_settings_file, aliases: true) }

  let(:example_config_yaml_file) do
    "#{@config_dir}/config.yaml".tap do |filename|
      config = base_config.merge(
        "schema_artifacts" => {"directory" => ::File.join(ElasticGraph::CommonSpecHelpers::REPO_ROOT, "config", "schema", "artifacts")}
      )
      config = ElasticGraph::Support::HashUtil.deep_merge(config, config_overrides_in_yaml)

      ::File.write(filename, ::YAML.dump(config))
    end
  end

  def expect_loading_lambda_to_define_constant(lambda:, const:)
    expect(::Object.const_defined?(const)).to be false

    # Loading the lambda function mutates are global set of constants. To isolate our tests,
    # we load it in a sub process--that keeps the parent test process "clean", helping to
    # prevent order-dependent test results.
    new_constants = in_sub_process do
      # Here we install and verify that the AWS lambda runtime is compatible with the current bundle of gems.
      # Importantly, we do this in a sub-process so that the monkey patches don't "leak" and impact our main test process!
      install_aws_lambda_runtime_monkey_patches

      orig_constants = ::Object.constants

      expect {
        load lambda
      }.to output(/Booting the lambda function/).to_stdout_from_any_process # silence standard logging

      yield ::Object.const_get(const)

      ::Object.constants - orig_constants
    end

    expect(new_constants).to include(const)
  end

  let(:cluster_test_urls) do
    base_config.fetch("datastore").fetch("clusters").transform_values do |cluster|
      cluster.fetch("url")
    end
  end

  define_method :with_lambda_env_vars do |cluster_urls: cluster_test_urls, extras: {}, &block|
    lambda_env_vars = {
      "ELASTICGRAPH_YAML_CONFIG" => example_config_yaml_file,
      "OPENSEARCH_CLUSTER_URLS" => ::JSON.generate(cluster_urls),
      "AWS_REGION" => "us-west-2",
      "AWS_ACCESS_KEY_ID" => "some-access-key",
      "AWS_SECRET_ACCESS_KEY" => "some-secret-key",
      "SENTRY_DSN" => "https://something@sentry.io/something"
    }.merge(extras)

    with_env(lambda_env_vars, &block)
  end

  # With the release of logger 1.6.0, and the release of faraday 2.10.0 (which depends on the `logger` gem for the first time),
  # it was discovered during a failed deploy that the AWS lambda Ruby runtime breaks logger 1.6.0 due to how it monkey patches it!
  # This caught us off guard since our CI build didn't fail with the same kind of error.
  #
  # We've fixed it by avoiding logger 1.6.0. To prevent a regression, and to identify future incompatibilities, here we load the
  # AWS Lambda Ruby runtime and install its monkey patches. We observed that this lead to the same kind of error as we saw during
  # the failed deploy before we pinned the logger version.
  #
  # Note: this method is only intended to be called from an `in_sub_process` block since it mutates the runtime environment.
  def install_aws_lambda_runtime_monkey_patches
    require "aws_lambda_ric/logger_patch"
    require "aws_lambda_ric"

    # The monkey patches are triggered by the act of instantiating this class:
    # https://github.com/aws/aws-lambda-ruby-runtime-interface-client/blob/3.0.0/lib/aws_lambda_ric.rb#L141-L152
    AwsLambdaRIC::TelemetryLogger.new("1") # File descriptor is required but not used in test env

    # Here we verify that the Logger monkey patch was indeed installed. The installation of the monkey patch
    # gets bypassed when certain errors are encountered (which are silently swallowed), so the mere act of
    # instantiating the class above doesn't guarantee the monkey patches are active.
    #
    # Plus, new versions of the `aws_lambda_ric` may change how the monkey patches are installed.
    #
    # https://github.com/aws/aws-lambda-ruby-runtime-interface-client/blob/3.0.0/lib/aws_lambda_ric.rb#L150-L152
    expect(::Logger.ancestors).to include(::LoggerPatch)

    expect {
      # Log a message to stdout--this is what triggered a `NoMethodError` when logger 1.6.0 is used.
      ::Logger.new($stdout).error("test log message")
    }.to output(a_string_including("test log message")).to_stdout_from_any_process
  end
end
