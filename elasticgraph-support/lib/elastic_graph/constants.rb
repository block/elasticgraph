# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Root namespace for all ElasticGraph code.
module ElasticGraph
  # Here we enumerate constants that are used from multiple places in the code.

  # The datastore date format used by ElasticGraph. Matches ISO-8601/RFC-3339.
  # See https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-date-format.html#built-in-date-formats
  # @private
  DATASTORE_DATE_FORMAT = "strict_date"

  # The datastore date time format used by ElasticGraph. Matches ISO-8601/RFC-3339.
  # See https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-date-format.html#built-in-date-formats
  # @private
  DATASTORE_DATE_TIME_FORMAT = "strict_date_time"

  # HTTP header that ElasticGraph HTTP implementations (e.g. elasticgraph-rack, elasticgraph-lambda)
  # look at to determine a client-specified request timeout.
  # @private
  TIMEOUT_MS_HEADER = "ElasticGraph-Request-Timeout-Ms"

  # Min/max values for the `Int` type.
  # Based on the GraphQL spec:
  #
  # > If the integer internal value represents a value less than -2^31 or greater
  # > than or equal to 2^31, a field error should be raised.
  #
  # (from http://spec.graphql.org/June2018/#sec-Int)
  # @private
  INT_MIN = -(2**31).to_int
  # @private
  INT_MAX = -INT_MIN - 1

  # Min/max values for our `JsonSafeLong` type.
  # Based on https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER
  # @private
  JSON_SAFE_LONG_MIN = -((2**53) - 1).to_int
  # @private
  JSON_SAFE_LONG_MAX = -JSON_SAFE_LONG_MIN

  # Min/max values for our `LongString` type.
  # This range is derived from the Elasticsearch docs on its longs:
  # > A signed 64-bit integer with a minimum value of -2^63 and a maximum value of 2^63 - 1.
  # (from https://www.elastic.co/guide/en/elasticsearch/reference/current/number.html)
  # @private
  LONG_STRING_MIN = -(2**63).to_int
  # @private
  LONG_STRING_MAX = -LONG_STRING_MIN - 1

  # When indexing large string values into the datastore, we've observed errors like:
  #
  # > bytes can be at most 32766 in length
  #
  # This is also documented on the Elasticsearch docs site, under "Choosing a keyword family field type":
  # https://www.elastic.co/guide/en/elasticsearch/reference/8.2/keyword.html#wildcard-field-type
  #
  # Note that it's a byte limit, but JSON schema's maxLength is a limit on the number of characters.
  # UTF8 uses up to 4 bytes per character so to guard against a maliciously crafted payload, we limit
  # the length to a quarter of 32766.
  # @private
  DEFAULT_MAX_KEYWORD_LENGTH = 32766 / 4

  # Strings indexed as `text` can be much larger than `keyword` fields. In fact, there's no limitation
  # on the `text` length, except for the overall size of the HTTP request body when we attempt to index
  # a `text` field. By default it's limited to 100MB via the `http.max_content_length` setting:
  #
  # https://www.elastic.co/guide/en/elasticsearch/reference/8.11/modules-network.html#http-settings
  #
  # Note: there's no guarantee that `text` values shorter than this will succeed when indexing them--it
  # depends on how many other fields and documents are included in the indexing payload, since the limit
  # is on the overall payload size, and not on the size of one field. Given that, there's not really a
  # discrete value we can use for the max length that guarantees successful indexing. But we know that
  # values larger than this will fail, so this is the limit we use.
  # @private
  DEFAULT_MAX_TEXT_LENGTH = 100 * (2**20).to_int

  # The name of the JSON schema definition for the ElasticGraph event envelope.
  # @private
  EVENT_ENVELOPE_JSON_SCHEMA_NAME = "ElasticGraphEventEnvelope"

  # For some queries, we wind up needing a pagination cursor for a collection
  # that will only ever contain a single value (and has no "key" to speak of
  # to encode into a cursor). In those contexts, we'll use this as the cursor value.
  # Ideally, we want this to be a value that could never be produced by our normal
  # cursor encoding logic. This cursor is encoded from data that includes a UUID,
  # which we can trust is unique.
  # @private
  SINGLETON_CURSOR = "eyJ1dWlkIjoiZGNhMDJkMjAtYmFlZS00ZWU5LWEwMjctZmVlY2UwYTZkZTNhIn0="

  # Schema artifact file names.
  # @private
  GRAPHQL_SCHEMA_FILE = "schema.graphql"
  # @private
  JSON_SCHEMAS_FILE = "json_schemas.yaml"
  # @private
  DATASTORE_CONFIG_FILE = "datastore_config.yaml"
  # @private
  RUNTIME_METADATA_FILE = "runtime_metadata.yaml"

  # Name for directory that contains versioned json_schemas files.
  # @private
  JSON_SCHEMAS_BY_VERSION_DIRECTORY = "json_schemas_by_version"
  # Name for field in json schemas files that represents schema "version".
  # @private
  JSON_SCHEMA_VERSION_KEY = "json_schema_version"

  # String that goes in the middle of a rollover index name, used to mark it as a rollover
  # index (and split on to parse a rollover index name).
  # @private
  ROLLOVER_INDEX_INFIX_MARKER = "_rollover__"

  # @private
  DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE = "Derived index update failed due to bad input data"

  # The current id of our static `index_data` update script. Verified by a test so you can count
  # on it being accurate. We expose this as a constant so that we can detect this specific script
  # in environments where we can't count on `elasticgraph-schema_definition` (where the script is
  # defined) being available, since that gem is usually only used in development.
  #
  # Note: this constant is automatically kept up-to-date by our `schema_artifacts:dump` rake task.
  # @private
  INDEX_DATA_UPDATE_SCRIPT_ID = "update_index_data_38ea36e5b48fc1566d4142e9fc44b12e"

  # The id of the old version of the update data script before ElasticGraph v0.9. For now, we are maintaining
  # backwards compatibility with how it recorded event versions, and we have test coverage for that which relies
  # upon this id.
  #
  # TODO: Drop this when we no longer need to maintain backwards-compatibility.
  # @private
  OLD_INDEX_DATA_UPDATE_SCRIPT_ID = "update_index_data_9b97090d5c97c4adc82dc7f4c2b89bc5"

  # When an update script has a no-op result we often want to communicate more information about
  # why it was a no-op back to ElatsicGraph from the script. The only way to do that is to throw
  # an exception with an error message, but, as far as I can tell, painless doesn't let you define
  # custom exception classes. To allow elasticgraph-indexer to detect that the script "failed" due
  # to a no-op (rather than a true failure) we include this common preamble in the exception message
  # thrown from our update scripts for the no-op case.
  # @private
  UPDATE_WAS_NOOP_MESSAGE_PREAMBLE = "ElasticGraph update was a no-op: "

  # The name used to refer to a document's own/primary source event (that is, the event that has a `type`
  # matching the document's type). The name here was chosen to avoid naming collisions with relationships
  # defined via the `relates_to_one`/`relates_to_many` APIs. The GraphQL spec reserves the double-underscore
  # prefix on field names, which means that users cannot define a relationship named `__self` via the
  # `relates_to_one`/`relates_to_many` APIs.
  # @private
  SELF_RELATIONSHIP_NAME = "__self"

  # This regex aligns with the datastore format of HH:mm:ss || HH:mm:ss.S || HH:mm:ss.SS || HH:mm:ss.SSS
  # See https://rubular.com/r/NHjBWrpZvzOTJO for examples.
  # @private
  VALID_LOCAL_TIME_REGEX = /\A(([0-1][0-9])|(2[0-3])):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,3})?\z/

  # `VALID_LOCAL_TIME_REGEX`, expressed as a JSON schema pattern. JSON schema supports a subset of
  # Ruby Regexp features and is expressed as a String object. Here we convert from the Ruby Regexp
  # start-and-end-of-string anchors (\A and \z) and convert them to the JSON schema ones (^ and $).
  #
  # For more info, see:
  # https://json-schema.org/understanding-json-schema/reference/regular_expressions.html
  # http://www.rexegg.com/regex-anchors.html
  # @private
  VALID_LOCAL_TIME_JSON_SCHEMA_PATTERN = VALID_LOCAL_TIME_REGEX.source.sub(/\A\\A/, "^").sub(/\\z\z/, "$")

  # Special hidden field defined in an index where we store the count of elements in each list field.
  # We index the list counts so that we can offer a `count` filter operator on list fields, allowing
  # clients to query on the count of list elements.
  #
  # The field name has a leading `__` because the GraphQL spec reserves that prefix for its own use,
  # and we can therefore assume that no GraphQL fields have this name.
  # @private
  LIST_COUNTS_FIELD = "__counts"

  # Character used to separate parts of a field path for the keys in the special `__counts`
  # field which contains the counts of the various list fields. We were going to use a dot
  # (as you'd expect) but ran into errors like this from the datastore:
  #
  # > can't merge a non object mapping [seasons.players.__counts.seasons] with an object mapping
  #
  # When we have a list of `object`, and then a list field on that object type, we want to
  # store the count of both the parent list and the child list, but if we use dots then the datastore
  # treats it like a nested JSON object, and the JSON entry at the parent path can't both be an integer
  # (for the parent list count) and an object containing counts of its child lists.
  #
  # By using `|` instead of `.`, we avoid this problem.
  # @private
  LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR = "|"

  # The set of datastore field types which have no `properties` in the mapping, but which
  # can be represented as a JSON object at indexing time.
  #
  # I built this list by auditing the full list of index field mapping types:
  # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/mapping-types.html
  # @private
  DATASTORE_PROPERTYLESS_OBJECT_TYPES = [
    "aggregate_metric_double", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/aggregate-metric-double.html
    "completion", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/search-suggesters.html#completion-suggester
    "flattened", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/flattened.html
    "geo_point", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/geo-point.html
    "geo_shape", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/geo-shape.html
    "histogram", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/histogram.html
    "join", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/parent-join.html
    "percolator", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/percolator.html
    "point", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/point.html
    "range", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/range.html
    "rank_features", # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/rank-features.html
    "shape" # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/shape.html
  ].to_set

  # This pattern matches the spec for a valid GraphQL name:
  # http://spec.graphql.org/June2018/#sec-Names
  #
  # ...however, it allows additional non-valid characters before and after it.
  # @private
  GRAPHQL_NAME_WITHIN_LARGER_STRING_PATTERN = /[_A-Za-z][_0-9A-Za-z]*/

  # This pattern exactly matches a valid GraphQL name, with no extra characters allowed before or after.
  # @private
  GRAPHQL_NAME_PATTERN = /\A#{GRAPHQL_NAME_WITHIN_LARGER_STRING_PATTERN}\z/

  # Description in English of the requirements for GraphQL names. (Used in multiple error messages).
  # @private
  GRAPHQL_NAME_VALIDITY_DESCRIPTION = "Names are limited to ASCII alphanumeric characters (plus underscore), and cannot start with a number."

  # The standard set of scalars that are defined by the GraphQL spec:
  # https://spec.graphql.org/October2021/#sec-Scalars
  # @private
  STOCK_GRAPHQL_SCALARS = %w[Boolean Float ID Int String].to_set.freeze

  # The current variant of JSON schema that we use.
  # @private
  JSON_META_SCHEMA = "http://json-schema.org/draft-07/schema#"

  # Filter the bulk response payload with a comma separated list using dot notation.
  # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/common-options.html#common-options-response-filtering
  #
  # Note: anytime you change this constant, be sure to check all the comments in the unit specs that mention this constant.
  # When stubbing a datastore client test double, it doesn't respect this filtering obviously, so it's up to us
  # to accurately mimic the filtering in our stubbed responses.
  # @private
  DATASTORE_BULK_FILTER_PATH = [
    # The key under `items` names the type of operation (e.g. `index` or `update`) and
    # we use a `*` for it since we always use that key, regardless of which operation it is.
    "items.*.status", "items.*.result", "items.*.error"
  ].join(",")

  # HTTP header set by `elasticgraph-graphql_lambda` to indicate the AWS ARN of the caller.
  # @private
  GRAPHQL_LAMBDA_AWS_ARN_HEADER = "X-AWS-LAMBDA-CALLER-ARN"

  # TODO(steep): it complains about `define_schema` not being defined but it is defined
  # in another file; I shouldn't have to say it's dynamic here. For now this works though.
  # @dynamic self.define_schema
end
