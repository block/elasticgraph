# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/update_target"
require "elastic_graph/schema_definition/indexing/derived_fields/append_only_set"
require "elastic_graph/schema_definition/indexing/derived_fields/immutable_value"
require "elastic_graph/schema_definition/indexing/derived_fields/min_or_max_value"
require "elastic_graph/schema_definition/scripting/script"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Used to configure the derivation of a derived indexed type from a source type.
      # This type is yielded from {Mixins::HasIndices#derive_indexed_type_fields}.
      #
      # @example Derive a `Course` type from `StudentCourseEnrollment` events
      #   ElasticGraph.define_schema do |schema|
      #     # `StudentCourseEnrollment` is a directly indexed type.
      #     schema.object_type "StudentCourseEnrollment" do |t|
      #       t.field "id", "ID"
      #       t.field "courseId", "ID"
      #       t.field "courseName", "String"
      #       t.field "studentName", "String"
      #       t.field "courseStartDate", "Date"
      #
      #       t.index "student_course_enrollments"
      #
      #       # Here we define how the `Course` indexed type  is derived when we index `StudentCourseEnrollment` events.
      #       t.derive_indexed_type_fields "Course", from_id: "courseId" do |derive|
      #         # `derive` is an instance of `DerivedIndexedType`.
      #         derive.immutable_value "name", from: "courseName"
      #         derive.append_only_set "students", from: "studentName"
      #         derive.min_value "firstOfferedDate", from: "courseStartDate"
      #         derive.max_value "mostRecentlyOfferedDate", from: "courseStartDate"
      #       end
      #     end
      #
      #     # `Course` is an indexed type that is derived entirely from `StudentCourseEnrollment` events.
      #     schema.object_type "Course" do |t|
      #       t.field "id", "ID"
      #       t.field "name", "String"
      #       t.field "students", "[String!]!"
      #       t.field "firstOfferedDate", "Date"
      #       t.field "mostRecentlyOfferedDate", "Date"
      #
      #       t.index "courses"
      #     end
      #   end
      #
      # @!attribute source_type
      #   @return [SchemaElements::ObjectType] the type used as a source for this derive type
      # @!attribute destination_type_ref
      #   @private
      # @!attribute id_source
      #   @return [String] path to field on the source type used as `id` on the derived type
      # @!attribute routing_value_source
      #   @return [String, nil] path to field on the source type used for shard routing
      # @!attribute rollover_timestamp_value_source
      #   @return [String, nil] path to field on the source type used as the timestamp field for rollover
      # @!attribute fields
      #   @return [Array<DerivedFields::AppendOnlySet, DerivedFields::ImmutableValue, DerivedFields::MinOrMaxValue>] derived field definitions
      class DerivedIndexedType < ::Struct.new(
        :source_type,
        :destination_type_ref,
        :id_source,
        :routing_value_source,
        :rollover_timestamp_value_source,
        :fields
      )
        # @param source_type [SchemaElements::ObjectType] the type used as a source for this derive type
        # @param destination_type_ref [SchemaElements::TypeReference] the derived type
        # @param id_source [String] path to field on the source type used as `id` on the derived type
        # @param routing_value_source [String, nil] path to field on the source type used for shard routing
        # @param rollover_timestamp_value_source [String, nil] path to field on the source type used as the timestamp field for rollover
        # @yield [DerivedIndexedType] the `DerivedIndexedType` instance
        # @api private
        def initialize(
          source_type:,
          destination_type_ref:,
          id_source:,
          routing_value_source:,
          rollover_timestamp_value_source:
        )
          fields = [] # : ::Array[_DerivedField]
          super(
            source_type: source_type,
            destination_type_ref: destination_type_ref,
            id_source: id_source,
            routing_value_source: routing_value_source,
            rollover_timestamp_value_source: rollover_timestamp_value_source,
            fields: fields
          )
          yield self
        end

        # Configures `field_name` (on the derived indexing type) to contain the set union of all values from
        # the `from` field on the source type. Values are only ever appended to the set, so the field will
        # act as an append-only set.
        #
        # @param field_name [String] name of field on the derived indexing type to store the derived set
        # @param from [String] path to field on the source type to source values from
        # @return [DerivedIndexedType::AppendOnlySet]
        #
        # @example
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "StudentCourseEnrollment" do |t|
        #       t.field "id", "ID"
        #       t.field "courseId", "ID"
        #       t.field "studentName", "String"
        #
        #       t.index "student_course_enrollments"
        #
        #       t.derive_indexed_type_fields "Course", from_id: "courseId" do |derive|
        #         derive.append_only_set "students", from: "studentName"
        #       end
        #     end
        #
        #     schema.object_type "Course" do |t|
        #       t.field "id", "ID"
        #       t.field "students", "[String!]!"
        #
        #       t.index "courses"
        #     end
        #   end
        def append_only_set(field_name, from:)
          fields << DerivedFields::AppendOnlySet.new(field_name, from)
        end

        # Configures `field_name` (on the derived indexing type) to contain a single immutable value from the
        # `from` field on the source type. Immutability is enforced by triggering an indexing failure with a
        # clear error if any event's source value is different from the value already indexed on this field.
        #
        # @param field_name [String] name of field on the derived indexing type to store the derived value
        # @param from [String] path to field on the source type to source values from
        # @param nullable [Boolean] whether the field is allowed to be set to `null`. When set to false, events
        #   that contain a `null` value in the `from` field will be rejected instead of setting the field’s value
        #   to `null`.
        # @param can_change_from_null [Boolean] whether a one-time mutation of the field value is allowed from
        #   `null` to a non-`null` value. This can be useful when dealing with a field that may not have a value
        #   on all source events. For example, if the source field was not initially part of the schema of your
        #   source dataset, you may have old records that lack a value for this field. When set, this option
        #   allows a one-time mutation of the field value from `null` to a non-`null` value. Once set to a
        #   non-`null` value, any additional `null` values that are encountered will be ignored (ensuring that
        #   the indexed data converges on the same state regardless of the order the events are ingested in).
        #   Note: this option cannot be enabled when `nullable: false` has been set.
        # @return [DerivedFields::ImmutableValue]
        #
        # @example
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "StudentCourseEnrollment" do |t|
        #       t.field "id", "ID"
        #       t.field "courseId", "ID"
        #       t.field "courseName", "String"
        #
        #       t.index "student_course_enrollments"
        #
        #       t.derive_indexed_type_fields "Course", from_id: "courseId" do |derive|
        #         derive.immutable_value "name", from: "courseName"
        #       end
        #     end
        #
        #     schema.object_type "Course" do |t|
        #       t.field "id", "ID"
        #       t.field "name", "String"
        #
        #       t.index "courses"
        #     end
        #   end
        def immutable_value(field_name, from:, nullable: true, can_change_from_null: false)
          if !nullable && can_change_from_null
            raise Errors::SchemaError, "`can_change_from_null: true` is not allowed with `nullable: false` (as there would be no `null` values to change from)."
          end

          fields << DerivedFields::ImmutableValue.new(
            destination_field: field_name,
            source_field: from,
            nullable: nullable,
            can_change_from_null: can_change_from_null
          )
        end

        # Configures `field_name` (on the derived indexing type) to contain the minimum of all values from the `from`
        # field on the source type.
        #
        # @param field_name [String] name of field on the derived indexing type to store the derived value
        # @param from [String] path to field on the source type to source values from
        # @return [DerivedIndexedType::MinOrMaxValue]
        #
        # @example
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "StudentCourseEnrollment" do |t|
        #       t.field "id", "ID"
        #       t.field "courseId", "ID"
        #       t.field "courseStartDate", "Date"
        #
        #       t.index "student_course_enrollments"
        #
        #       t.derive_indexed_type_fields "Course", from_id: "courseId" do |derive|
        #         derive.min_value "firstOfferedDate", from: "courseStartDate"
        #       end
        #     end
        #
        #     schema.object_type "Course" do |t|
        #       t.field "id", "ID"
        #       t.field "firstOfferedDate", "Date"
        #
        #       t.index "courses"
        #     end
        #   end
        def min_value(field_name, from:)
          fields << DerivedFields::MinOrMaxValue.new(field_name, from, :min)
        end

        # Configures `field_name` (on the derived indexing type) to contain the maximum of all values from the `from`
        # field on the source type.
        #
        # @param field_name [String] name of field on the derived indexing type to store the derived value
        # @param from [String] path to field on the source type to source values from
        # @return [DerivedIndexedType::MinOrMaxValue]
        #
        # @example
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "StudentCourseEnrollment" do |t|
        #       t.field "id", "ID"
        #       t.field "courseId", "ID"
        #       t.field "courseStartDate", "Date"
        #
        #       t.index "student_course_enrollments"
        #
        #       t.derive_indexed_type_fields "Course", from_id: "courseId" do |derive|
        #         derive.max_value "mostRecentlyOfferedDate", from: "courseStartDate"
        #       end
        #     end
        #
        #     schema.object_type "Course" do |t|
        #       t.field "id", "ID"
        #       t.field "mostRecentlyOfferedDate", "Date"
        #
        #       t.index "courses"
        #     end
        #   end
        def max_value(field_name, from:)
          fields << DerivedFields::MinOrMaxValue.new(field_name, from, :max)
        end

        # @return [Scripting::Script] Painless script that will maintain the derived fields
        # @api private
        def painless_script
          Scripting::Script.new(
            source: generate_script.strip,
            name: "#{destination_type_ref}_from_#{source_type.name}",
            language: "painless",
            context: "update"
          )
        end

        # @return [SchemaArtifacts::RuntimeMetadata::UpdateTarget] runtime metadata for the source type
        # @api private
        def runtime_metadata_for_source_type
          SchemaArtifacts::RuntimeMetadata::UpdateTarget.new(
            type: destination_type_ref.name,
            relationship: nil,
            script_id: painless_script.id,
            id_source: id_source,
            routing_value_source: routing_value_source,
            rollover_timestamp_value_source: rollover_timestamp_value_source,
            metadata_params: {},
            data_params: fields.map(&:source_field).to_h do |f|
              [f, SchemaArtifacts::RuntimeMetadata::DynamicParam.new(source_path: f, cardinality: :many)]
            end
          )
        end

        private

        def generate_script
          if fields.empty?
            raise Errors::SchemaError, "`derive_indexed_type_fields` definition for #{destination_type_ref} (from #{source_type.name}) " \
              "has no derived field definitions."
          end

          sorted_fields = fields.sort_by(&:destination_field)

          # We use `uniq` here to avoid re-doing the same setup multiple times, since multiple fields can sometimes
          # need the same setup (such as initializing a common parent field to an empty map).
          function_defs = sorted_fields.flat_map(&:function_definitions).uniq.map(&:strip).sort

          setup_statements = [STATIC_SETUP_STATEMENTS] + sorted_fields.flat_map(&:setup_statements).uniq.map(&:strip)

          apply_update_statements = sorted_fields.map { |f| apply_update_statement(f).strip }

          # Note: comments in the script are effectively "free" since:
          #
          #   - The compiler will strip them out.
          #   - We only send the script to the datastore once (when configuring the cluster), and later
          #     reference it only by id--so we don't pay for the larger payload on each indexing request.
          <<~EOS
            #{function_defs.join("\n\n")}

            #{setup_statements.join("\n")}

            #{apply_update_statements.join("\n")}

            if (!#{SCRIPT_ERRORS_VAR}.isEmpty()) {
              throw new IllegalArgumentException("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: " + #{SCRIPT_ERRORS_VAR}.join(" "));
            }

            // For records with no new values to index, only skip the update if the document itself doesn't already exist.
            // Otherwise create an (empty) document to reflect the fact that the id has been seen.
            if (ctx._source.id != null && #{sorted_fields.map { |f| was_noop_variable(f) }.join(" && ")}) {
              ctx.op = 'none';
            } else {
              // Here we set `_source.id` because if we don't, it'll never be set, making these docs subtly
              // different from docs indexed the normal way.
              //
              // Note also that we MUST use `params.id` instead of `ctx._id`. The latter works on an update
              // of an existing document, but is unavailable when we are inserting the document for the first time.
              ctx._source.id = params.id;
            }
          EOS
        end

        def apply_update_statement(field)
          "boolean #{was_noop_variable(field)} = !#{field.apply_operation_returning_update_status};"
        end

        def was_noop_variable(field)
          "#{field.destination_field.gsub(".", "__")}_was_noop"
        end

        SCRIPT_ERRORS_VAR = "scriptErrors"

        STATIC_SETUP_STATEMENTS = <<~EOS.strip
          Map data = params.data;
          // A variable to accumulate script errors so that we can surface _all_ issues and not just the first.
          List #{SCRIPT_ERRORS_VAR} = new ArrayList();
        EOS
      end
    end
  end
end
