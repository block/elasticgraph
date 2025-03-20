# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Apollo
    module SchemaDefinition
      # Namespace for mixins that provide support for Apollo's [federation directives](https://www.apollographql.com/docs/federation/federated-schemas/federated-directives/).
      # Each Apollo federation directive is offered via an API starting with `apollo`. For example, `apollo_key` can be used to define an
      # Apollo `@key`.
      module ApolloDirectives
        # Supports Apollo's [`@authenticated` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#authenticated).
        module Authenticated
          # Adds the [`@authenticated` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#authenticated)
          # to the schema element.
          #
          # @return [void]
          #
          # @example Add `@authenticated` to a type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.apollo_authenticated
          #     end
          #   end
          def apollo_authenticated
            directive "authenticated"
          end
        end

        # Supports Apollo's [`@extends` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#extends).
        module Extends
          # Adds the [`@extends` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#extends)
          # to the schema element.
          #
          # @return [void]
          #
          # @example Add `@extends` to a type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.apollo_extends
          #     end
          #   end
          def apollo_extends
            directive "extends"
          end
        end

        # Supports Apollo's [`@external` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#external).
        module External
          # Adds the [`@external` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#external)
          # to the schema element.
          #
          # @return [void]
          #
          # @example Add `@external` to a type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.apollo_external
          #     end
          #   end
          def apollo_external
            directive "external"
          end
        end

        # Supports Apollo's [`@inaccessible` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#inaccessible).
        module Inaccessible
          # Adds the [`@inaccessible` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#inaccessible)
          # to the schema element.
          #
          # @return [void]
          #
          # @example Add `@inaccessible` to a type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.apollo_inaccessible
          #     end
          #   end
          def apollo_inaccessible
            directive "inaccessible"
          end
        end

        # Supports Apollo's [`@interfaceObject` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#interfaceobject).
        module InterfaceObject
          # Adds the [`@interfaceObject` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#interfaceobject)
          # to the schema element.
          #
          # @return [void]
          #
          # @example Add `@interfaceObject` to a type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.apollo_interface_object
          #     end
          #   end
          def apollo_interface_object
            directive "interfaceObject"
          end
        end

        # Supports Apollo's [`@key` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#key).
        module Key
          # Adds the [`@key` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#key)
          # to the schema element.
          #
          # @param fields [String] A GraphQL selection set (provided as a string) of fields and subfields that contribute to the entity's
          #   unique key.
          # @param resolvable [Boolean] If false, indicates to the Apollo router that this subgraph doesn't define a reference resolver for
          #   this entity. This means that router query plans can't "jump to" this subgraph to resolve fields that aren't defined in another
          #   subgraph.
          # @return [void]
          #
          # @example Define a `@key` on a non-indexed type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.field "organizationId", "ID"
          #       t.field "id", "ID"
          #       t.apollo_key fields: "id organizationId", resolvable: false
          #     end
          #   end
          #
          # @note ElasticGraph automatically defines an `apollo_key` of `id` for every indexed type. This API is only needed when defining
          #   additional keys on an indexed type, or defining a key for a non-indexed type.
          def apollo_key(fields:, resolvable: true)
            directive "key", fields: fields, resolvable: resolvable
          end
        end

        # Supports Apollo's [`@override` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#override).
        module Override
          # Adds the [`@override` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#override)
          # to the schema element.
          #
          # @param from [String] The name of the other subgraph that no longer resolves the field.
          # @return [void]
          #
          # @example Add `@override` to a field
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Product" do |t|
          #       t.field "inStock", "Boolean" do |f|
          #         f.apollo_override from: "Products"
          #       end
          #     end
          #   end
          def apollo_override(from:)
            directive "override", from: from
          end
        end

        # Supports Apollo's [`@policy` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#policy).
        module Policy
          # Adds the [`@policy` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#policy)
          # to the schema element.
          #
          # @param policies [Array<String>] List of authorization policies.
          # @return [void]
          #
          # @example Add `@policy` to a type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.apollo_policy policies: ["Policy1", "Policy2"]
          #     end
          #   end
          def apollo_policy(policies:)
            directive "policy", policies: policies
          end
        end

        # Supports Apollo's [`@provides` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#provides).
        module Provides
          # Adds the [`@provides` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#provides)
          # to the schema element.
          #
          # @param fields [String] A GraphQL selection set (provided as a string) of object fields and subfields that the subgraph can
          #   resolve only at this query path.
          # @return [void]
          #
          # @example Add `@provides` to a field
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Product" do |t|
          #       t.field "name", "String"
          #     end
          #
          #     schema.object_type "StoreLocation" do |t|
          #       t.field "products", "[Product!]!" do |f|
          #         f.mapping type: "nested"
          #         f.apollo_provides fields: "name"
          #       end
          #     end
          #   end
          def apollo_provides(fields:)
            directive "provides", fields: fields
          end
        end

        # Supports Apollo's [`@requires` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#requires).
        module Requires
          # Adds the [`@requires` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#requires)
          # to the schema element.
          #
          # @param fields [String] A GraphQL selection set (provided as a string) of object fields and subfields that the subgraph can
          #   resolve only at this query path.
          # @return [void]
          #
          # @example Add `@requires` to a field
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Product" do |t|
          #       t.field "size", "Int"
          #       t.field "weight", "Int"
          #       t.field "shippingEstimate", "String" do |f|
          #         f.apollo_requires fields: "size weight"
          #       end
          #     end
          #   end
          def apollo_requires(fields:)
            directive "requires", fields: fields
          end
        end

        # Supports Apollo's [`@requiresScopes` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#requiresscopes).
        module RequiresScopes
          # Adds the [`@requiresScopes` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#requiresscopes)
          # to the schema element.
          #
          # @param scopes [Array<String>] List of JWT scopes that must be granted to the user in order to access the underlying element data.
          # @return [void]
          #
          # @example Add `@requiresScopes` to a field
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Product" do |t|
          #       t.field "shippingEstimate", "String" do |f|
          #         f.apollo_requires_scopes scopes: "shipping"
          #       end
          #     end
          #   end
          def apollo_requires_scopes(scopes:)
            directive "requiresScopes", scopes: scopes
          end
        end

        # Supports Apollo's [`@shareable` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#shareable).
        module Shareable
          # Adds the [`@shareable` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#shareable)
          # to the schema element.
          #
          # @return [void]
          #
          # @example Add `@shareable` to a type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.apollo_shareable
          #     end
          #   end
          def apollo_shareable
            directive "shareable"
          end
        end

        # Supports Apollo's [`@tag` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#tag).
        module Tag
          # Adds the [`@tag` directive](https://www.apollographql.com/docs/federation/federated-types/federated-directives/#tag)
          # to the schema element.
          #
          # @return [void]
          #
          # @example Add `@tag` to a type
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Campaign" do |t|
          #       t.apollo_tag name: "public"
          #     end
          #   end
          #
          # @see APIExtension#tag_built_in_types_with
          # @see FieldExtension#tag_with
          def apollo_tag(name:)
            directive "tag", name: name
          end
        end
      end
    end
  end
end
