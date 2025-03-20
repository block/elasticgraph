# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # @private
  module Errors
    class Error < StandardError
    end

    class CursorEncoderError < Error
    end

    class InvalidSortFieldsError < CursorEncoderError
    end

    class InvalidCursorError < CursorEncoderError
    end

    class CursorEncodingError < CursorEncoderError
    end

    class CountUnavailableError < Error
    end

    class InvalidArgumentValueError < Error
    end

    class InvalidMergeError < Error
    end

    class SchemaError < Error
    end

    class InvalidGraphQLNameError < SchemaError
    end

    class NotFoundError < Error
    end

    class SearchFailedError < Error
    end

    class RequestExceededDeadlineError < SearchFailedError
    end

    class IdentifyDocumentVersionsFailedError < Error
    end

    class IndexOperationError < Error
    end

    class ClusterOperationError < Error
    end

    class InvalidExtensionError < Error
    end

    class ConfigError < Error
    end

    class ConfigSettingNotSetError < ConfigError
    end

    class InvalidScriptDirectoryError < Error
    end

    class MissingSchemaArtifactError < Error
    end

    class S3OperationFailedError < Error
    end

    class MessageIdsMissingError < Error
    end

    class BadDatastoreRequest < Error
    end
  end
end
