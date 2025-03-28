# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/extension"
require "elastic_graph/schema_artifacts/runtime_metadata/graphql_resolver"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/results"
require "elastic_graph/schema_definition/state"

module ElasticGraph
  # The main entry point for schema definition from ElasticGraph applications.
  #
  # Call this API from a Ruby file configured as the `path_to_schema` (or from a Ruby file
  # `load`ed from the `path_to_schema` file).
  #
  # @example
  #   ElasticGraph.define_schema do |schema|
  #     # The `schema` object provides the schema definition API. Use it in this block.
  #   end
  def self.define_schema
    if (api_instance = ::Thread.current[:ElasticGraph_SchemaDefinition_API_instance])
      yield api_instance
    else
      raise Errors::SchemaError, "No active `SchemaDefinition::API` instance is available. " \
        "Let ElasticGraph load the schema definition files."
    end
  end

  # Provides the ElasticGraph schema definition API. The primary entry point is {.define_schema}.
  module SchemaDefinition
    # Root API object that provides the schema definition API.
    #
    # @example
    #   ElasticGraph.define_schema do |schema|
    #     # The `schema` object is an instance of `API`
    #   end
    class API
      include Mixins::HasReadableToSAndInspect.new

      # @dynamic state, factory

      # @return [State] object which holds all state for the schema definition
      attr_reader :state

      # @return [Factory] object responsible for instantiating all schema element classes
      attr_reader :factory

      # @private
      def initialize(
        schema_elements,
        index_document_sizes,
        extension_modules: [],
        derived_type_name_formats: {},
        type_name_overrides: {},
        enum_value_overrides_by_type: {},
        output: $stdout
      )
        @state = State.with(
          api: self,
          schema_elements: schema_elements,
          index_document_sizes: index_document_sizes,
          derived_type_name_formats: derived_type_name_formats,
          type_name_overrides: type_name_overrides,
          enum_value_overrides_by_type: enum_value_overrides_by_type,
          output: output
        )

        @factory = @state.factory

        extension_modules.each { |mod| extend(mod) }

        # These lines must come _after_ the extension modules are applied, so that the extension modules
        # have a chance to hook into the factory in order to customize built in types if desired.
        @factory.new_built_in_types(self).register_built_in_types
        @state.initially_registered_built_in_types.merge(@state.types_by_name.keys)
      end

      # Defines a raw GraphQL SDL snippet that will be included in the generated `schema.graphql` artifact. Designed to be an escape hatch,
      # for when ElasticGraph doesn’t provide another way to write some type of GraphQL SDL element that you need. Currently, the only
      # known use case is to define custom GraphQL directives.
      #
      # @param string [String] Raw snippet of SDL
      # @return [void]
      #
      # @example Define a custom directive and use it
      #   ElasticGraph.define_schema do |schema|
      #     # Define a directive we can use to annotate what system a data type comes from.
      #     schema.raw_sdl "directive @sourcedFrom(system: String!) on OBJECT"
      #
      #     schema.object_type "Transaction" do |t|
      #       t.directive "sourcedFrom", system: "transaction-processor"
      #     end
      #   end
      def raw_sdl(string)
        @state.sdl_parts << string
        nil
      end

      # Defines a [GraphQL object type](https://graphql.org/learn/schema/#object-types-and-fields) Use it to define a concrete type that
      # has subfields. Object types can either be _indexed_ (e.g. directly indexed in the datastore, and available to query from the
      # root `Query` object) or _embedded_ in other indexed types.
      #
      # @param name [String] name of the object type
      # @yield [SchemaElements::ObjectType] object type object
      # @return [void]
      #
      # @example Define embedded and indexed object types
      #   ElasticGraph.define_schema do |schema|
      #     # `Money` is an embedded object type
      #     schema.object_type "Money" do |t|
      #       t.field "currency", "String"
      #       t.field "amount", "JsonSafeLong"
      #     end
      #
      #     # `Transaction` is an indexed object type
      #     schema.object_type "Transaction" do |t|
      #       t.root_query_fields plural: "transactions"
      #       t.field "id", "ID"
      #       t.field "cost", "Money"
      #       t.index "transactions"
      #     end
      #   end
      def object_type(name, &block)
        @state.register_object_interface_or_union_type @factory.new_object_type(name.to_s, &block)
        nil
      end

      # Defines a [GraphQL interface](https://graphql.org/learn/schema/#interface-types). Use it to define an abstract supertype with
      # one or more fields that concrete implementations of the interface must also define. Each implementation can be an
      # {SchemaElements::ObjectType} or {SchemaElements::InterfaceType}.
      #
      # @param name [String] name of the interface
      # @yield [SchemaElements::InterfaceType] interface type object
      # @return [void]
      #
      # @example Define an interface and implement it
      #   ElasticGraph.define_schema do |schema|
      #     schema.interface_type "Athlete" do |t|
      #       t.field "name", "String"
      #       t.field "team", "String"
      #     end
      #
      #     schema.object_type "BaseballPlayer" do |t|
      #       t.implements "Athlete"
      #       t.field "name", "String"
      #       t.field "team", "String"
      #       t.field "battingAvg", "Float"
      #     end
      #
      #     schema.object_type "BasketballPlayer" do |t|
      #       t.implements "Athlete"
      #       t.field "name", "String"
      #       t.field "team", "String"
      #       t.field "pointsPerGame", "Float"
      #     end
      #   end
      def interface_type(name, &block)
        @state.register_object_interface_or_union_type @factory.new_interface_type(name.to_s, &block)
        nil
      end

      # Defines a [GraphQL enum type](https://graphql.org/learn/schema/#enum-types).
      # The type is restricted to an enumerated set of values, each with a unique name.
      # Use `value` or `values` to define the enum values in the passed block.
      #
      # Note: if required by your configuration, this may generate a pair of Enum types (an input
      # enum and an output enum).
      #
      # @param name [String] name of the enum type
      # @yield [SchemaElements::EnumType] enum type object
      # @return [void]
      #
      # @example Define an enum type
      #   ElasticGraph.define_schema do |schema|
      #     schema.enum_type "Currency" do |t|
      #       t.value "USD" do |v|
      #         v.documentation "US Dollars."
      #       end
      #
      #       t.value "JPY" do |v|
      #         v.documentation "Japanese Yen."
      #       end
      #
      #       # You can define multiple values in one call if you don't care about their docs or directives.
      #       t.values "GBP", "AUD"
      #     end
      #   end
      def enum_type(name, &block)
        @state.register_enum_type @factory.new_enum_type(name.to_s, &block)
        nil
      end

      # Defines a [GraphQL union type](https://graphql.org/learn/schema/#union-types). Use it to define an abstract supertype with one or
      # more concrete subtypes. Each subtype must be an {SchemaElements::ObjectType}, but they do not have to share any fields in common.
      #
      # @param name [String] name of the union type
      # @yield [SchemaElements::UnionType] union type object
      # @return [void]
      #
      # @example Define a union type
      #   ElasticGraph.define_schema do |schema|
      #     schema.object_type "Card" do |t|
      #       # ...
      #     end
      #
      #     schema.object_type "BankAccount" do |t|
      #       # ...
      #     end
      #
      #     schema.object_type "BitcoinWallet" do |t|
      #       # ...
      #     end
      #
      #     schema.union_type "FundingSource" do |t|
      #       t.subtype "Card"
      #       t.subtypes "BankAccount", "BitcoinWallet"
      #     end
      #   end
      def union_type(name, &block)
        @state.register_object_interface_or_union_type @factory.new_union_type(name.to_s, &block)
        nil
      end

      # Defines a [GraphQL scalar type](https://graphql.org/learn/schema/#scalar-types). ElasticGraph itself uses this to define a few
      # common scalar types (e.g. `Date` and `DateTime`), but it is also available to you to use to define your own custom scalar types.
      #
      # @param name [String] name of the scalar type
      # @yield [SchemaElements::ScalarType] scalar type object
      # @return [void]
      #
      # @example Define a scalar type
      #   ElasticGraph.define_schema do |schema|
      #     schema.scalar_type "URL" do |t|
      #       t.mapping type: "keyword"
      #       t.json_schema type: "string", format: "uri"
      #     end
      #   end
      def scalar_type(name, &block)
        @state.register_scalar_type @factory.new_scalar_type(name.to_s, &block)
        nil
      end

      # Registers the name of a type that existed in a prior version of the schema but has been deleted.
      #
      # @note In situations where this API applies, ElasticGraph will give you an error message indicating that you need to use this API
      #   or {SchemaElements::TypeWithSubfields#renamed_from}. Likewise, when ElasticGraph no longer needs to know about this, it'll give you a warning
      #   indicating the call to this method can be removed.
      #
      # @param name [String] name of type that used to exist but has been deleted
      # @return [void]
      #
      # @example Indicate that `Widget` has been deleted
      #   ElasticGraph.define_schema do |schema|
      #     schema.deleted_type "Widget"
      #   end
      def deleted_type(name)
        @state.register_deleted_type(
          name,
          defined_at: caller_locations(1, 1).to_a.first, # : ::Thread::Backtrace::Location
          defined_via: %(schema.deleted_type "#{name}")
        )
        nil
      end

      # Registers a GraphQL extension module that will be loaded and used by `elasticgraph-graphql`. While such
      # extension modules can also be configured in a settings YAML file, it can be useful to register it here
      # when you want to ensure that the extension is used in all environments. For example, an extension library
      # that defines custom schema elements (such as `elasticgraph-apollo`) may need to ensure its corresponding
      # GraphQL extension module is used since the custom schema elements would not work correctly otherwise.
      #
      # @param extension_module [Module] GraphQL extension module
      # @param defined_at [String] the `require` path of the extension module
      # @param extension_config [Hash<Symbol, Object>] configuration options for the extension module
      # @return [void]
      #
      # @example Register `elasticgraph-query_registry` extension module
      #   require(query_registry_require_path = "elastic_graph/query_registry/graphql_extension")
      #
      #   ElasticGraph.define_schema do |schema|
      #     schema.register_graphql_extension ElasticGraph::QueryRegistry::GraphQLExtension,
      #       defined_at: query_registry_require_path
      #   end
      def register_graphql_extension(extension_module, defined_at:, **extension_config)
        @state.graphql_extension_modules << SchemaArtifacts::RuntimeMetadata::Extension.new(extension_module, defined_at, extension_config)
        nil
      end

      # Registers a GraphQL resolver that will be loaded and used by `elasticgraph-graphql`. To use a GraphQL resolver you have
      # registered, set a field's `resolver` to the name you provide when registering your resolver.
      #
      # @param name [Symbol] unique name of the resolver
      # @param klass [Class] resolver class
      # @param defined_at [String] the `require` path of the resolver
      # @param resolver_config [Hash<Symbol, Object>] configuration options for the resolver, to support parameterized resolvers
      # @return [void]
      #
      # @example Register a custom resolver for use by a custom `Query` field
      #   # In `add_resolver.rb`:
      #   class AddResolver
      #     def initialize(elasticgraph_graphql:, config:)
      #     end
      #
      #     def resolve(field:, object:, args:, context:, lookahead:)
      #       args.fetch("x") + args.fetch("y")
      #     end
      #   end
      #
      #   # In `config/schema.rb`:
      #   ElasticGraph.define_schema do |schema|
      #     require(resolver_path = "add_resolver")
      #     schema.register_graphql_resolver :add, AddResolver, defined_at: resolver_path
      #
      #     schema.on_root_query_type do |t|
      #       t.field "add", "Int" do |f|
      #         f.argument "x", "Int!"
      #         f.argument "y", "Int!"
      #         f.resolver = :add
      #       end
      #     end
      #   end
      def register_graphql_resolver(name, klass, defined_at:, **resolver_config)
        extension = SchemaArtifacts::RuntimeMetadata::Extension.new(klass, defined_at, resolver_config)
        extension.verify_against!(SchemaArtifacts::RuntimeMetadata::GraphQLResolver::Interface)

        resolver = SchemaArtifacts::RuntimeMetadata::GraphQLResolver.new(
          needs_lookahead: true,
          resolver_ref: extension.to_dumpable_hash
        )

        @state.graphql_resolvers_by_name[name] = resolver
        nil
      end

      # @return the results of the schema definition
      def results
        @results ||= Results.new(@state)
      end

      # Defines the version number of the current JSON schema. Importantly, every time a change is made that impacts the JSON schema
      # artifact, the version number must be incremented to ensure that each different version of the JSON schema is identified by a unique
      # version number. The publisher will then include this version number in published events to identify the version of the schema it
      # was using. This avoids the need to deploy the publisher and ElasticGraph indexer at the same time to keep them in sync.
      #
      # @note While this is an important part of how ElasticGraph is designed to support schema evolution, it can be annoying constantly
      #   have to increment this while rapidly changing the schema during prototyping. You can disable the requirement to increment this
      #   on every JSON schema change by setting `enforce_json_schema_version` to `false` in your `Rakefile`.
      #
      # @param version [Integer] current version number of the JSON schema artifact
      # @return [void]
      # @see Local::RakeTasks#enforce_json_schema_version
      #
      # @example Set the JSON schema version to 1
      #   ElasticGraph.define_schema do |schema|
      #     schema.json_schema_version 1
      #   end
      def json_schema_version(version)
        if !version.is_a?(Integer) || version < 1
          raise Errors::SchemaError, "`json_schema_version` must be a positive integer. Specified version: #{version}"
        end

        if @state.json_schema_version
          raise Errors::SchemaError, "`json_schema_version` can only be set once on a schema. Previously-set version: #{@state.json_schema_version}"
        end

        @state.json_schema_version = version
        @state.json_schema_version_setter_location = caller_locations(1, 1).to_a.first
        nil
      end

      # Registers a customization callback that will be applied to every built-in type automatically provided by ElasticGraph. Provides
      # an opportunity to customize the built-in types (e.g. to add directives to them or whatever).
      #
      # @yield [SchemaElements::EnumType, SchemaElements::InputType, SchemaElements::InterfaceType, SchemaElements::ObjectType, SchemaElements::ScalarType, SchemaElements::UnionType] built in type
      # @return [void]
      #
      # @example Customize documentation of built-in types
      #   ElasticGraph.define_schema do |schema|
      #     schema.on_built_in_types do |type|
      #       type.append_to_documentation "This is a built-in ElasticGraph type."
      #     end
      #   end
      def on_built_in_types(&customization_block)
        @state.built_in_types_customization_blocks << customization_block
        nil
      end

      # Registers a customization callback that will be applied to the root `Query` type when it is generated.
      #
      # @yield [SchemaElements::ObjectType] the root `Query` type
      # @return [void]
      #
      # @example Customize documentation of built-in types
      #   ElasticGraph.define_schema do |schema|
      #     schema.on_root_query_type do |type|
      #       type.append_to_documentation "This schema has been generated by ElasticGraph."
      #     end
      #   end
      def on_root_query_type(&customization_block)
        on_built_in_types do |type|
          customization_block.call(_ = type) if type.name == "Query"
        end
        nil
      end

      # While the block executes, makes any `ElasticGraph.define_schema` calls operate on this `API` instance.
      #
      # @private
      def as_active_instance
        # @type var old_value: API?
        old_value = ::Thread.current[:ElasticGraph_SchemaDefinition_API_instance]
        ::Thread.current[:ElasticGraph_SchemaDefinition_API_instance] = self
        yield
      ensure
        ::Thread.current[:ElasticGraph_SchemaDefinition_API_instance] = old_value
      end
    end
  end
end
