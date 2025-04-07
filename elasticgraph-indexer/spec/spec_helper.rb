# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-indexer`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

require "delegate"

module ElasticGraph
  module IndexerSpecHelpers
    class UseOldUpdateScripts < ::SimpleDelegator
      def script_id
        OLD_INDEX_DATA_UPDATE_SCRIPT_ID
      end

      def for_normal_indexing?
        true
      end
    end

    def with_use_updates_for_indexing(config, use_updates_for_indexing)
      config.with(index_definitions: config.index_definitions.transform_values do |index_def|
        index_def.with(use_updates_for_indexing: use_updates_for_indexing)
      end)
    end

    def build_indexer(use_old_update_script: false, **options, &block)
      return super(**options, &block) unless use_old_update_script

      schema_artifacts = SchemaArtifacts::FromDisk.new(::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema", "artifacts"))

      schema_artifacts.runtime_metadata.object_types_by_name.each do |name, object_type|
        object_type.update_targets.map! do |update_target|
          if update_target.for_normal_indexing?
            UseOldUpdateScripts.new(update_target)
          else
            update_target
          end
        end
      end

      super(schema_artifacts: schema_artifacts, **options, &block)
    end
  end

  module UseUpdatesForIndexingTrue
    def build_indexer(**options)
      super do |config|
        with_use_updates_for_indexing(config, true)
      end
    end
  end

  module UseUpdatesForIndexingFalse
    def build_indexer(**options)
      super do |config|
        with_use_updates_for_indexing(config, false)
      end
    end

    module WithFactories
      # standard:disable Lint/UnderscorePrefixedVariableName
      def build(type, __version: nil, **attributes)
        # The default strategy our factories use for `__version` works for `use_updates_for_indexing: true`,
        # but not for `use_updates_for_indexing: false`. When `use_updates_for_indexing` is `false`, our indexing
        # calls compare the document's version against the event version. Our "delete all documents" cleanup
        # that gets performed before every integration or acceptance test impacts this as well: the datastore
        # remembers the `version` of a deleted document, and if you try indexing a new payload for that document
        # with a lower version, it'll reject it. During local development, we do not restart the datastore between
        # every `rspec` run (that would slow us down a ton...), which means that the datastore's memory of the
        # versions of documents deleted in a prior test run can impact a later test run.
        #
        # Here we use a monotonic clock to guarantee that every factory-generated record has a higher version than
        # every previously generated record--including ones generated on prior test runs. Note that on OS X it appears
        # that the system clock does not return nanosecond precision times (the last 3 digits are consistently 000...) =
        # but we trust that will never generate multiple factory records for the same record type and id on the exact
        # same microsecond so it should be sufficient.
        __version ||= Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

        super(type, __version: __version, **attributes)
      end
      # standard:enable Lint/UnderscorePrefixedVariableName
    end
  end

  RSpec.configure do |config|
    config.define_derived_metadata(absolute_file_path: %r{/elasticgraph-indexer/}) do |meta|
      meta[:builds_indexer] = true
    end

    config.prepend IndexerSpecHelpers, absolute_file_path: %r{/elasticgraph-indexer/}
    config.include UseUpdatesForIndexingTrue, use_updates_for_indexing: true
    config.include UseUpdatesForIndexingFalse, use_updates_for_indexing: false
    config.prepend UseUpdatesForIndexingFalse::WithFactories, use_updates_for_indexing: false, factories: true
  end
end
