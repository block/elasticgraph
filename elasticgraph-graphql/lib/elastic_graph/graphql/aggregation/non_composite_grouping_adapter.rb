# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Aggregation
      # Grouping adapter that avoids using a `composite` aggregation, due to limitations with Elasticsearch/OpenSearch.
      module NonCompositeGroupingAdapter
        class << self
          def meta_name
            "non_comp"
          end

          def grouping_detail_for(query)
            date_groupings, term_groupings = query.groupings.partition do |grouping|
              grouping.is_a?(DateHistogramGrouping)
            end

            grouping_detail(date_groupings, query) do
              # We want term groupings inside date groupings so that, when our bucket aggregations might produce
              # inaccurate doc counts, the innermost grouping aggregation has `doc_count_error_upper_bound` on
              # its buckets allowing us to expose information about the accuracy.
              #
              # Date histogram aggregations do not include `doc_count_error_upper_bound` because, on their own, they are
              # always accurate, but they may not be accurate when used as a sub-aggregation of a `terms` aggregation.
              #
              # For more detail on the issue this ordering is designed to avoid, see:
              # https://discuss.elastic.co/t/accuracy-of-date-histogram-sub-aggregation-doc-count-under-terms-aggregation/348685
              grouping_detail(term_groupings, query) do
                inner_clauses = yield
                inner_clauses = nil if inner_clauses.empty?
                AggregationDetail.new(inner_clauses, {})
              end
            end
          end

          def prepare_response_buckets(sub_agg, buckets_path, meta)
            sort_and_truncate_buckets(format_buckets(sub_agg, buckets_path), meta.fetch("size"))
          end

          private

          def grouping_detail(groupings, query)
            # Our `reduce` here builds the date grouping clauses from the inside out (since each reduction step
            # wraps the prior step's result in an outer `aggs` hash). The natural result of that is a nested set of
            # date grouping clauses that "feels" inside-out compared to what you would naturally expect.
            #
            # While that causes no concrete issue, it's nice to avoid. Here we use `reverse` to correct for that.
            groupings.reverse.reduce(yield) do |inner_detail, grouping|
              inner_detail.wrap_with_grouping(grouping, query: query)
            end
          end

          # Formats the result of a bucket aggregation into a format that we can easily resolve. There are two things
          # this accomplishes:
          #
          # - Converts bucket keys into hashes that can be used to resolve `grouped_by` fields.
          # - Recursively flattens multiple levels of aggregations (which happens when we need to mix multiple kinds of
          #   bucket aggregations to group in the way the client requested) into a single flat list.
          def format_buckets(sub_agg, buckets_path, parent_key_fields: {}, parent_key_values: [])
            agg_with_buckets = sub_agg.dig(*buckets_path)

            missing_bucket = {
              # Doc counts in missing value buckets are always perfectly accurate.
              "doc_count_error_upper_bound" => 0
            }.merge(sub_agg.dig(*missing_bucket_path_from(buckets_path))) # : ::Hash[::String, untyped]

            meta = agg_with_buckets.fetch("meta")

            grouping_field_names = meta.fetch("grouping_fields") # provides the names of the fields being grouped on
            key_path = meta.fetch("key_path") # indicates whether we want to get the key values from `key` or `key_as_string`.
            sub_buckets_path = meta["buckets_path"] # buckets_path is optional, so we don't use fetch.
            merge_into_bucket = meta.fetch("merge_into_bucket")

            raw_buckets = agg_with_buckets.fetch("buckets") # : ::Array[::Hash[::String, untyped]]

            # If the missing bucket is non-empty, include it. This matches the behavior of composite aggregations
            # when the `missing_bucket` option is used.
            raw_buckets += [missing_bucket] if missing_bucket.fetch("doc_count") > 0

            raw_buckets.flat_map do |raw_bucket|
              # The key will either be a single value (e.g. `47`) if we used a `terms`/`date_histogram` aggregation,
              # or a tuple of values (e.g. `[47, "abc"]`) if we used a `multi_terms` aggregation. Here we convert it
              # to the form needed for resolving `grouped_by` fields: a hash like `{"size" => 47, "tag" => "abc"}`.
              key_values = Array(raw_bucket.dig(*key_path))
              key_fields_hash = grouping_field_names.zip(key_values).to_h

              # If we have multiple levels of aggregations, we need to merge the key fields hash with the key fields from the parent levels.
              key_fields = parent_key_fields.merge(key_fields_hash)
              key_values = parent_key_values + key_values

              # If there's another level of aggregations, `buckets_path` will provide us with the path to that next level.
              # We can use it to recurse as we build a flat list of buckets.
              if sub_buckets_path
                format_buckets(raw_bucket, sub_buckets_path, parent_key_fields: key_fields, parent_key_values: key_values)
              else
                [raw_bucket.merge(merge_into_bucket).merge({"key" => key_fields, "key_values" => key_values})]
              end
            end
          end

          # A `terms` or `multi_terms` sub-aggregation is automatically sorted by `doc_count` and we pass
          # `size` to the datastore to limit the number of returned buckets.
          #
          # A `date_histogram` sub-aggregation is sorted ascending by the date, and we don't limit the buckets
          # in any way (there's no `size` parameter).
          #
          # To honor the requested page size and return buckets in a consistent order, we sort the buckets here
          # (by doc count descending, then by the key values ascending), and then take only first `size`.
          def sort_and_truncate_buckets(buckets, size)
            buckets
              .sort_by do |b|
                # We convert key values to strings to ensure they are comparable. Otherwise, we can get an error like:
                #
                # > ArgumentError: comparison of Array with Array failed
                #
                # Note that this turns it into a lexicographical sort rather than a more type-aware sort
                # (10 will sort before 2, for example), but that's fine. We only sort by `key_values` as
                # a time breaker to ensure deterministic results, but don't particularly care which buckets
                # come first.
                [-b.fetch("doc_count"), b.fetch("key_values").map(&:to_s)]
              end.first(size)
          end

          def missing_bucket_path_from(buckets_path)
            *all_but_last, last = buckets_path
            all_but_last + [Key.missing_value_bucket_key(last.to_s)]
          end
        end
      end
    end
  end
end
