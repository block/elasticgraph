# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../gemspec_helper"

ElasticGraphGemspecHelper.define_elasticgraph_gem(gemspec_file: __FILE__, category: :lambda) do |spec, eg_version|
  spec.summary = "ElasticGraph gem that monitors OpenSearch CPU utilization to autoscale indexer lambda concurrency."

  spec.add_dependency "elasticgraph-datastore_core", eg_version
  spec.add_dependency "elasticgraph-lambda_support", eg_version

  spec.add_dependency "aws-sdk-lambda", "~> 1.125"
  spec.add_dependency "aws-sdk-sqs", "~> 1.80"
  spec.add_dependency "aws-sdk-cloudwatch", "~> 1.104"

  # aws-sdk-sqs requires an XML library be available. On Ruby < 3 it'll use rexml from the standard library but on Ruby 3.0+
  # we have to add an explicit dependency. It supports ox, oga, libxml, nokogiri or rexml, and of those, ox seems to be the
  # best choice: it leads benchmarks, is well-maintained, has no dependencies, and is MIT-licensed.
  spec.add_dependency "ox", "~> 2.14"

  spec.add_development_dependency "elasticgraph-elasticsearch", eg_version
  spec.add_development_dependency "elasticgraph-opensearch", eg_version
end
