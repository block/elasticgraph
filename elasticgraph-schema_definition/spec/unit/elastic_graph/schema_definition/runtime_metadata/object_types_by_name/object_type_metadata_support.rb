# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.shared_context "object type metadata support" do
      include_context "RuntimeMetadata support"

      def object_types_by_name(**options, &block)
        runtime_metadata = define_schema(**options, &block).runtime_metadata
        runtime_metadata = SchemaArtifacts::RuntimeMetadata::Schema.from_hash(runtime_metadata.to_dumpable_hash, for_context: :admin)
        runtime_metadata.object_types_by_name
      end

      def object_type_metadata_for(*names, **options, &block)
        if names.one?
          object_types_by_name(**options, &block)[names.first]
        else
          metadata = object_types_by_name(**options, &block)
          names.map { |name| metadata[name] }
        end
      end

      def self.on_a_type_union_or_interface_type(&block)
        context "on a type union" do
          include ObjectTypeMetadataUnionTypeImplementation
          module_exec(:union_type, &block)
        end

        context "on an interface type" do
          include ObjectTypeMetadataInterfaceTypeImplementation
          module_exec(:interface_type, &block)
        end
      end
    end

    module ObjectTypeMetadataUnionTypeImplementation
      def link_subtype_to_supertype(object_type, supertype_name)
        # nothing to do; the linkage happens via a `subtypes` call on the supertype
      end

      def link_supertype_to_subtypes(union_type, *subtype_names)
        union_type.subtypes(*subtype_names)
      end
    end

    module ObjectTypeMetadataInterfaceTypeImplementation
      def link_subtype_to_supertype(object_type, interface_name)
        object_type.implements interface_name
      end

      def link_supertype_to_subtypes(interface_type, *subtype_names)
        # nothing to do; the linkage happens via an `implements` call on the subtype
      end
    end
  end
end
