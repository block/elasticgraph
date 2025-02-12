# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/version"
require "elastic_graph/apollo/graphql/engine_extension"
require "elastic_graph/apollo/schema_definition/entity_type_extension"
require "elastic_graph/apollo/schema_definition/factory_extension"
require "elastic_graph/apollo/schema_definition/state_extension"

module ElasticGraph
  # ElasticGraph extension library that implements the [Apollo subgraph federation
  # spec](https://www.apollographql.com/docs/federation/subgraph-spec/), turning
  # any ElasticGraph instance into an Apollo subgraph.
  #
  # `ElasticGraph::Apollo` has two parts:
  #
  # * {Apollo::SchemaDefinition} is an extension used while defining an ElasticGraph schema. It includes all schema elements that are part
  #   of the Apollo spec, including `_Entity` and the various directives.
  # * {Apollo::GraphQL} is an extension used by `elasticgraph-graphql` to support queries against Apollo's subgraph schema additions (e.g.
  #   `_service` and `_entities`). It includes [reference resolvers](https://www.apollographql.com/docs/federation/entities/#2-define-a-reference-resolver)
  #   for all indexed types in your schema.
  #
  # To use `elasticgraph-apollo`, simply use {Apollo::SchemaDefinition::APIExtension} as a schema definition extension module. The GraphQL
  # extension module will get used by `elasticgraph-graphql` automatically.
  #
  # @example Use elasticgraph-apollo in a project
  #   require "elastic_graph/apollo/schema_definition/api_extension"
  #
  #   ElasticGraph::Local::RakeTasks.new(
  #     local_config_yaml: "config/settings/local.yaml",
  #     path_to_schema: "config/schema.rb"
  #   ) do |tasks|
  #     tasks.schema_definition_extension_modules = [ElasticGraph::Apollo::SchemaDefinition::APIExtension]
  #   end
  module Apollo
    # Namespace for all Apollo schema definition support.
    #
    # {SchemaDefinition::APIExtension} is the primary entry point and should be used as a schema definition extension module.
    module SchemaDefinition
      # Module designed to be extended onto an {ElasticGraph::SchemaDefinition::API} instance
      # to customize the schema artifacts based on the [Apollo Federation subgraph
      # spec](https://www.apollographql.com/docs/federation/subgraph-spec/).
      #
      # To use this module, pass it in `schema_definition_extension_modules` when defining your {ElasticGraph::Local::RakeTasks}.
      #
      # @example Define local rake tasks with this extension module
      #   require "elastic_graph/apollo/schema_definition/api_extension"
      #
      #   ElasticGraph::Local::RakeTasks.new(
      #     local_config_yaml: "config/settings/local.yaml",
      #     path_to_schema: "config/schema.rb"
      #   ) do |tasks|
      #     tasks.schema_definition_extension_modules = [ElasticGraph::Apollo::SchemaDefinition::APIExtension]
      #   end
      module APIExtension
        # Applies an apollo tag to built-in types so that they are included in the Apollo contract schema.
        #
        # @param name [String] tag name
        # @param except [Array<String>] built-in types not to tag
        # @return [void]
        # @see ApolloDirectives::Tag
        # @see FieldExtension#tag_with
        #
        # @example Tag all built-in types (except two) for inclusion in the `public` schema
        #   ElasticGraph.define_schema do |schema|
        #     schema.tag_built_in_types_with "public", except: ["IntAggregatedValue", "FloatAggregatedValues"]
        #   end
        def tag_built_in_types_with(name, except: [])
          except_set = except.to_set
          on_built_in_types do |type|
            apollo_type = (_ = type) # : ApolloDirectives::Tag
            apollo_type.apollo_tag(name: name) unless except_set.include?(type.name)
          end
        end

        # Picks which version of Apollo federation to target. By default, the latest supported version is
        # targeted, but you can call this to pick an earlier version, which may be necessary if your
        # organization is on an older version of Apollo federation.
        #
        # @param version [String] version number
        # @return [void]
        #
        # @example Set the Apollo Federation Version
        #   ElasticGraph.define_schema do |schema|
        #     schema.target_apollo_federation_version "2.6"
        #   end
        def target_apollo_federation_version(version)
          # Allow the version to have the `v` prefix, but don't require it.
          version = version.delete_prefix("v")

          state.apollo_directive_definitions = DIRECTIVE_DEFINITIONS_BY_FEDERATION_VERSION.fetch(version) do
            supported_version_descriptions = DIRECTIVE_DEFINITIONS_BY_FEDERATION_VERSION.keys.map do |version_number|
              "v#{version_number}"
            end.join(", ")

            raise Errors::SchemaError, "elasticgraph-apollo v#{ElasticGraph::VERSION} does not support Apollo federation v#{version}. " \
              "Pick one of the supported versions (#{supported_version_descriptions}) instead."
          end
        end

        def self.extended(api)
          api.factory.extend FactoryExtension
          api.state.extend StateExtension

          latest_federation_version = DIRECTIVE_DEFINITIONS_BY_FEDERATION_VERSION
            .keys
            .max_by { |v| v.split(".").map(&:to_i) } # : ::String

          api.target_apollo_federation_version latest_federation_version

          api.on_built_in_types do |type|
            # Built-in types like `PageInfo` need to be tagged with `@shareable` on Federation V2 since other subgraphs may
            # have them and they aren't entity types. `Query`, as the root, is a special case that must be skipped.
            # We also need to customize it.
            if type.name == "Query"
              customize_root_query_type(_ = type)
            elsif type.respond_to?(:apollo_shareable)
              (_ = type).apollo_shareable
            end
          end

          api.register_graphql_extension GraphQL::EngineExtension, defined_at: "elastic_graph/apollo/graphql/engine_extension"
          api.state.after_user_definition_complete do
            api.send(:define_apollo_schema_elements)
          end
        end

        private

        # These directive definitions come straight from the Apollo federation spec:
        # https://github.com/apollographql/federation/blob/25beb382fff253ac38ef6d7a5454af60da0addbb/docs/source/subgraph-spec.mdx#L57-L70
        # https://github.com/apollographql/apollo-federation-subgraph-compatibility/blob/2.0.0/COMPATIBILITY.md#products-schema-to-be-implemented-by-library-maintainers
        #
        # I've updated them here to match the "canonical form" that the GraphQL
        # gem dumps for directives (e.g. it sorts the `on` clauses alphabetically) so that
        # we can use this from our tests to assert the resulting GraphQL SDL.
        directives_for_fed_v2_6 = [
          <<~EOS.strip,
            extend schema
              @link(import: ["@authenticated", "@composeDirective", "@extends", "@external", "@inaccessible", "@interfaceObject", "@key", "@override", "@policy", "@provides", "@requires", "@requiresScopes", "@shareable", "@tag", "FieldSet"], url: "https://specs.apollo.dev/federation/v2.6")
          EOS
          "directive @authenticated on ENUM | FIELD_DEFINITION | INTERFACE | OBJECT | SCALAR",
          "directive @composeDirective(name: String!) repeatable on SCHEMA",
          "directive @extends on INTERFACE | OBJECT",
          "directive @external on FIELD_DEFINITION | OBJECT",
          "directive @inaccessible on ARGUMENT_DEFINITION | ENUM | ENUM_VALUE | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | INPUT_OBJECT | INTERFACE | OBJECT | SCALAR | UNION",
          "directive @interfaceObject on OBJECT",
          "directive @key(fields: FieldSet!, resolvable: Boolean = true) repeatable on INTERFACE | OBJECT",
          "directive @link(as: String, for: link__Purpose, import: [link__Import], url: String!) repeatable on SCHEMA",
          "directive @override(from: String!) on FIELD_DEFINITION",
          "directive @policy(policies: [[federation__Policy!]!]!) on ENUM | FIELD_DEFINITION | INTERFACE | OBJECT | SCALAR",
          "directive @provides(fields: FieldSet!) on FIELD_DEFINITION",
          "directive @requires(fields: FieldSet!) on FIELD_DEFINITION",
          "directive @requiresScopes(scopes: [[federation__Scope!]!]!) on ENUM | FIELD_DEFINITION | INTERFACE | OBJECT | SCALAR",
          "directive @shareable on FIELD_DEFINITION | OBJECT",
          "directive @tag(name: String!) repeatable on ARGUMENT_DEFINITION | ENUM | ENUM_VALUE | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | INPUT_OBJECT | INTERFACE | OBJECT | SCALAR | UNION"
        ]

        # Differences between federation v2.5 and v2.6
        #
        # - v2.5 has no @policy directive (v2.6 has this).
        # - The link URL reflects the version
        directives_for_fed_v2_5 = directives_for_fed_v2_6.filter_map do |directive|
          if directive.include?("extend schema")
            directive
              .sub(', "@policy"', "")
              .sub("v2.6", "v2.5")
          elsif directive.include?("directive @policy")
            nil
          else
            directive
          end
        end

        # Differences between federation v2.3 and v2.5
        #
        # - v2.3 has no @authenticated directive (v2.5 has this).
        # - v2.3 has no @requiresScopes directive (v2.5 has this).
        # - The link URL reflects the version
        directives_for_fed_v2_3 = directives_for_fed_v2_5.filter_map do |directive|
          if directive.include?("extend schema")
            directive
              .sub('"@authenticated", ', "")
              .sub(', "@requiresScopes"', "")
              .sub("v2.5", "v2.3")
          elsif directive.include?("directive @authenticated") || directive.include?("directive @requiresScopes")
            nil
          else
            directive
          end
        end

        # Differences between federation v2.0 and v2.3
        #
        # - v2.0 has no @composeDirective directive (v2.3 has this).
        # - v2.0 has no @interfaceObject directive (v2.3 has this).
        # - The link URL reflects the version
        directives_for_fed_v2_0 = directives_for_fed_v2_3.filter_map do |directive|
          if directive.include?("extend schema")
            directive
              .sub('"@composeDirective", ', "")
              .sub(', "@interfaceObject"', "")
              .sub("v2.3", "v2.0")
          elsif directive.include?("directive @interfaceObject") || directive.include?("directive @composeDirective")
            nil
          else
            directive
          end
        end

        DIRECTIVE_DEFINITIONS_BY_FEDERATION_VERSION = {
          "2.6" => directives_for_fed_v2_6,
          "2.5" => directives_for_fed_v2_5,
          "2.3" => directives_for_fed_v2_3,
          "2.0" => directives_for_fed_v2_0
        }

        def define_apollo_schema_elements
          state.apollo_directive_definitions.each { |directive| raw_sdl directive }

          apollo_scalar_type "link__Import" do |t|
            t.documentation "Scalar type used by the `@link` directive required for Apollo Federation V2."
            # `scalar_type` requires we set these but this scalar type is only in GraphQL.
            t.mapping type: nil
            t.json_schema type: "null"
          end

          apollo_scalar_type "federation__Scope" do |t|
            t.documentation "Scalar type used by the `@requiresScopes` directive required for Apollo Federation V2.5+."
            # `scalar_type` requires we set these but this scalar type is only in GraphQL.
            t.mapping type: nil
            t.json_schema type: "null"
          end

          apollo_scalar_type "federation__Policy" do |t|
            t.documentation "Scalar type used by the `@policy` directive required for Apollo Federation V2.6+."
            # `scalar_type` requires we set these but this scalar type is only in GraphQL.
            t.mapping type: nil
            t.json_schema type: "null"
          end

          # Copied from https://github.com/apollographql/federation/blob/b3a3cb84d8d67d1d6e817dc85b9ae0ecdd9908d1/docs/source/subgraph-spec.mdx#subgraph-schema-additions
          apollo_enum_type "link__Purpose" do |t|
            t.documentation "Enum type used by the `@link` directive required for Apollo Federation V2."

            t.value "SECURITY" do |v|
              v.documentation "`SECURITY` features provide metadata necessary to securely resolve fields."
            end

            t.value "EXECUTION" do |v|
              v.documentation "`EXECUTION` features provide metadata necessary for operation execution."
            end
          end

          apollo_scalar_type "FieldSet" do |t|
            t.documentation <<~EOS
              A custom scalar type required by the [Apollo Federation subgraph
              spec](https://www.apollographql.com/docs/federation/subgraph-spec/#scalar-fieldset):

              > This string-serialized scalar represents a set of fields that's passed to a federated directive,
              > such as `@key`, `@requires`, or `@provides`.
              >
              > Grammatically, a `FieldSet` is a [selection set](http://spec.graphql.org/draft/#sec-Selection-Sets)
              > minus the outermost curly braces. It can represent a single field (`"upc"`), multiple fields
              > (`"id countryCode"`), and even nested selection sets (`"id organization { id }"`).

              Not intended for use by clients other than Apollo.
            EOS

            # `scalar_type` requires we set these but this scalar type is only in GraphQL.
            t.mapping type: nil
            t.json_schema type: "null"
          end

          apollo_scalar_type "_Any" do |t|
            t.documentation <<~EOS
              A custom scalar type required by the [Apollo Federation subgraph
              spec](https://www.apollographql.com/docs/federation/subgraph-spec/#scalar-_any):

              > This scalar is the type used for entity **representations** that the graph router
              > passes to the `Query._entities` field. An `_Any` scalar is validated by matching
              > its `__typename` and `@key` fields against entities defined in the subgraph schema.
              >
              > An `_Any` is serialized as a JSON object, like so:
              >
              > ```
              > {
              >   "__typename": "Product",
              >   "upc": "abc123"
              > }
              > ```

              Not intended for use by clients other than Apollo.
            EOS

            # `scalar_type` requires we set these but this scalar type is only in GraphQL.
            t.mapping type: nil
            t.json_schema type: "null"
          end

          apollo_object_type "_Service" do |t|
            t.documentation <<~EOS
              An object type required by the [Apollo Federation subgraph
              spec](https://www.apollographql.com/docs/federation/subgraph-spec/#type-_service):

              > This object type must have an `sdl: String!` field, which returns the SDL of the subgraph schema as a string.
              >
              > - The returned schema string _must_ include all uses of federation-specific directives (`@key`, `@requires`, etc.).
              > - **If supporting Federation 1,** the schema _must not_ include any definitions from [Subgraph schema additions](https://www.apollographql.com/docs/federation/subgraph-spec/#subgraph-schema-additions).
              >
              > For details, see [Enhanced introspection with `Query._service`](https://www.apollographql.com/docs/federation/subgraph-spec/#enhanced-introspection-with-query_service).

              Not intended for use by clients other than Apollo.
            EOS

            t.field "sdl", "String", graphql_only: true do |f|
              f.documentation <<~EOS
                A field required by the [Apollo Federation subgraph
                spec](https://www.apollographql.com/docs/federation/subgraph-spec/#required-resolvers-for-introspection):

                > The returned `sdl` string has the following requirements:
                >
                > - It must **include** all uses of all federation-specific directives, such as `@key`.
                >     - All of these directives are shown in [Subgraph schema additions](https://www.apollographql.com/docs/federation/subgraph-spec/#subgraph-schema-additions).
                > - **If supporting Federation 1,** `sdl` must **omit** all automatically added definitions from
                >   [Subgraph schema additions](https://www.apollographql.com/docs/federation/subgraph-spec/#subgraph-schema-additions),
                >   such as `Query._service` and `_Service.sdl`!
                >     - If your library is _only_ supporting Federation 2, `sdl` can include these definitions.

                Not intended for use by clients other than Apollo.
              EOS
            end
          end

          entity_types = state.object_types_by_name.values.select do |object_type|
            object_type.directives.any? do |directive|
              directive.name == "key" && directive.arguments.fetch(:resolvable, true)
            end
          end

          validate_entity_types_can_all_be_resolved(entity_types)

          entity_type_names = entity_types
            # As per the GraphQL spec[1], only object types can be in a union, and interface
            # types cannot be in a union. The GraphQL gem has validation[2] for this and will raise
            # an error if we violate it, so we must filter to only object types here.
            #
            # [1] https://spec.graphql.org/October2021/#sec-Unions.Type-Validation
            # [2] https://github.com/rmosolgo/graphql-ruby/pull/3024
            .grep(ElasticGraph::SchemaDefinition::SchemaElements::ObjectType)
            .map(&:name)

          unless entity_type_names.empty?
            apollo_union_type "_Entity" do |t|
              t.extend EntityTypeExtension
              t.documentation <<~EOS
                A union type required by the [Apollo Federation subgraph
                spec](https://www.apollographql.com/docs/federation/subgraph-spec/#union-_entity):

                > **⚠️ This union type is generated dynamically based on the input subgraph schema!**
                >
                > This union's possible types must include all entities that the subgraph defines.
                > It's the return type of the `Query._entities` field, which the graph router uses
                > to directly access a subgraph's entity fields.
                >
                > For details, see [Defining the `_Entity` union](https://www.apollographql.com/docs/federation/subgraph-spec/#defining-the-_entity-union).

                In an ElasticGraph schema, this is a union of all indexed types.

                Not intended for use by clients other than Apollo.
              EOS

              t.subtypes(*entity_type_names)
            end
          end
        end

        def apollo_object_type(name, &block)
          object_type name do |type|
            type.graphql_only true
            yield type
          end
        end

        def apollo_union_type(name, &block)
          union_type name do |type|
            type.graphql_only true
            yield type
          end
        end

        def apollo_scalar_type(name, &block)
          scalar_type name do |type|
            type.graphql_only true
            yield type
          end
        end

        def apollo_enum_type(name, &block)
          enum_type name do |type|
            type.graphql_only true
            yield type
          end
        end

        # state comes from object we extend with this module.
        # @dynamic state

        def validate_entity_types_can_all_be_resolved(entity_types)
          unresolvable_field_errors =
            entity_types.reject(&:indexed?).filter_map do |object_type|
              key_field_names = object_type.directives
                .select { |dir| dir.name == "key" }
                # https://rubular.com/r/JEuYKzqnyR712A
                .flat_map { |dir| dir.arguments[:fields].to_s.gsub(/{.*}/, "").split(" ") }
                .to_set

              unresolvable_fields = object_type.graphql_fields_by_name.values.reject do |field|
                key_field_names.include?(field.name) ||
                  field.relationship ||
                  field.directives.any? { |directive| directive.name == "external" }
              end

              if unresolvable_fields.any?
                <<~EOS.strip
                  `#{object_type.name}` has fields that ElasticGraph will be unable to resolve when Apollo requests it as an entity:

                  #{unresolvable_fields.map { |field| "  * `#{field.name}`" }.join("\n")}

                  On a resolvable non-indexed entity type like this, ElasticGraph can only resolve `@key` fields and
                  `relates_to_(one|many)` fields. To fix this, either add `resolvable: false` to the `apollo_key` or
                  do one of the following for each unresolvable field:

                    * Add it to the `apollo_key`
                    * Redefine it as a relationship
                    * Use `field.apollo_external` so Apollo knows how to treat it
                    * Remove it
                EOS
              end
            end

          if unresolvable_field_errors.any?
            raise Errors::SchemaError, unresolvable_field_errors.join("\n#{"-" * 100}\n")
          end
        end

        private_class_method def self.customize_root_query_type(type)
          if type.schema_def_state.object_types_by_name.values.any?(&:indexed?)
            type.field "_entities", "[_Entity]!", graphql_only: true do |f|
              f.documentation <<~EOS
                A field required by the [Apollo Federation subgraph
                spec](https://www.apollographql.com/docs/federation/subgraph-spec/#query_entities):

                > The graph router uses this root-level `Query` field to directly fetch fields of entities defined by a subgraph.
                >
                > This field must take a `representations` argument of type `[_Any!]!` (a non-nullable list of non-nullable
                > [`_Any` scalars](https://www.apollographql.com/docs/federation/subgraph-spec/#scalar-_any)). Its return type must be `[_Entity]!` (a non-nullable list of _nullable_
                > objects that belong to the [`_Entity` union](https://www.apollographql.com/docs/federation/subgraph-spec/#union-_entity)).
                >
                > Each entry in the `representations` list  must be validated with the following rules:
                >
                > - A representation must include a `__typename` string field.
                > - A representation must contain all fields included in the fieldset of a `@key` directive applied to the corresponding entity definition.
                >
                > For details, see [Resolving entity fields with `Query._entities`](https://www.apollographql.com/docs/federation/subgraph-spec/#resolving-entity-fields-with-query_entities).

                Not intended for use by clients other than Apollo.
              EOS

              f.argument "representations", "[_Any!]!" do |a|
                a.documentation <<~EOS
                  A list of entity data blobs from other apollo subgraphs. For more information (and
                  to see an example of what form this argument takes), see the [Apollo Federation subgraph
                  spec](https://www.apollographql.com/docs/federation/subgraph-spec/#resolve-requests-for-entities).
                EOS
              end

              f.resolver = :apollo_entities
            end
          end

          type.field "_service", "_Service!", graphql_only: true do |f|
            f.documentation <<~EOS
              A field required by the [Apollo Federation subgraph
              spec](https://www.apollographql.com/docs/federation/subgraph-spec/#query_service):

              > This field of the root `Query` type must return a non-nullable [`_Service` type](https://www.apollographql.com/docs/federation/subgraph-spec/#type-_service).

              > For details, see [Enhanced introspection with `Query._service`](https://www.apollographql.com/docs/federation/subgraph-spec/#enhanced-introspection-with-query_service).

              Not intended for use by clients other than Apollo.
            EOS

            f.resolver = :apollo_service
          end
        end
      end
    end
  end
end
