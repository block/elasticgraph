# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Mixin for types that can implement interfaces ({SchemaElements::ObjectType} and {SchemaElements::InterfaceType}).
      module ImplementsInterfaces
        # Declares that the current type implements the specified interface, making the current type a subtype of the interface. The
        # current type must define all of the fields of the named interface, with the exact same field types.
        #
        # @param interface_names [Array<String>] names of interface types implemented by this type
        # @return [void]
        #
        # @example Implement an interface
        #  ElasticGraph.define_schema do |schema|
        #    schema.interface_type "Athlete" do |t|
        #      t.field "name", "String"
        #      t.field "team", "String"
        #    end
        #
        #    schema.object_type "BaseballPlayer" do |t|
        #      t.implements "Athlete"
        #      t.field "name", "String"
        #      t.field "team", "String"
        #      t.field "battingAvg", "Float"
        #    end
        #
        #    schema.object_type "BasketballPlayer" do |t|
        #      t.implements "Athlete"
        #      t.field "name", "String"
        #      t.field "team", "String"
        #      t.field "pointsPerGame", "Float"
        #    end
        #  end
        def implements(*interface_names)
          interface_refs = interface_names.map do |interface_name|
            schema_def_state.type_ref(interface_name).to_final_form.tap do |interface_ref|
              implementations = schema_def_state.implementations_by_interface_ref[interface_ref] # : ::Set[SchemaElements::TypeWithSubfields]
              implementations << self
            end
          end

          implemented_interfaces.concat(interface_refs)
        end

        # @return [Array<SchemaElements::TypeReference>] list of type references for the interface types implemented by this type
        def implemented_interfaces
          @implemented_interfaces ||= []
        end

        # Called after the schema definition is complete, before dumping artifacts. Here we validate
        # the correctness of interface implementations. We defer it until this time to not require the
        # interface and fields to be defined before the `implements` call.
        #
        # Note that the GraphQL gem on its own supports a form of "interface inheritance": if declaring
        # that an object type implements an interface, and the object type is missing one or more of the
        # interface fields, the GraphQL gem dynamically adds the missing interface fields to the object
        # type (at least, that's the result I noted when dumping the GraphQL SDL after trying that!).
        # However, we cannot allow that, because our schema definition is used to generate non-GrapQL
        # artifacts (e.g. the JSON schema and the index mapping), and all the artifacts must agree
        # on the fields. Therefore, we use this method to verify that the object type fully implements
        # the specified interfaces.
        #
        # @return [void]
        # @private
        def verify_graphql_correctness!
          schema_error_messages = implemented_interfaces.filter_map do |interface_ref|
            interface = interface_ref.resolved

            case interface
            when SchemaElements::InterfaceType
              differences = (_ = interface).interface_fields_by_name.values.filter_map do |interface_field|
                my_field_sdl = graphql_fields_by_name[interface_field.name]&.to_sdl(type_structure_only: true)
                interface_field_sdl = interface_field.to_sdl(type_structure_only: true)

                if my_field_sdl.nil?
                  "missing `#{interface_field.name}`"
                elsif my_field_sdl != interface_field_sdl
                  "`#{interface_field_sdl.strip}` vs `#{my_field_sdl.strip}`"
                end
              end

              unless differences.empty?
                "Type `#{name}` does not correctly implement interface `#{interface_ref}` " \
                  "due to field differences: #{differences.join("; ")}."
              end
            when nil
              "Type `#{name}` cannot implement `#{interface_ref}` because `#{interface_ref}` is not defined."
            else
              "Type `#{name}` cannot implement `#{interface_ref}` because `#{interface_ref}` is not an interface."
            end
          end

          unless schema_error_messages.empty?
            raise Errors::SchemaError, schema_error_messages.join("\n\n")
          end
        end

        # @yield [SchemaElements::Argument] an argument
        # @yieldreturn [Boolean] whether or not to include the argument in the generated GraphQL SDL
        # @return [String] SDL string of the type
        def to_sdl(&field_arg_selector)
          name_section =
            if implemented_interfaces.empty?
              name
            else
              # Include all ancestor interfaces in SDL
              all_interfaces = recursively_resolve_supertypes.grep(SchemaElements::InterfaceType)
              "#{name} implements #{all_interfaces.map(&:name).sort.join(" & ")}"
            end

          generate_sdl(name_section: name_section, &field_arg_selector)
        end

        # Returns all supertypes of this type, including union memberships and interface ancestors.
        #
        # @return [Set<UnionType, InterfaceType>] set of supertypes
        # @private
        def recursively_resolve_supertypes
          recursively_resolve_supertypes_from(initial_interface_chain)
        end

        private

        def recursively_resolve_supertypes_from(interface_chain)
          union_memberships = schema_def_state.union_types_by_member_ref[type_ref]

          interface_supertypes = implemented_interfaces.flat_map do |interface_ref|
            interface = interface_ref.resolved

            if interface_chain.include?(interface_ref.name)
              raise Errors::SchemaError, "Your schema has self-referential types, which are not allowed, since " \
                "it prevents the datastore mapping and GraphQL schema generation from terminating:\n" \
                "- The set of #{(interface_chain + [interface_ref.name]).uniq.inspect} forms a circular reference chain."
            end

            [interface] + interface.send(:recursively_resolve_supertypes_from, interface_chain + [interface_ref.name]).to_a
          end.to_set

          union_memberships | interface_supertypes
        end

        def initial_interface_chain
          is_a?(SchemaElements::InterfaceType) ? [name] : []
        end
      end
    end
  end
end
