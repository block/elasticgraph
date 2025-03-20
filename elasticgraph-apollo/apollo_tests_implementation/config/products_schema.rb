# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# @private
module ApolloTestImpl
  federation_version = ENV["TARGET_APOLLO_FEDERATION_VERSION"]

  # Note: this includes many "manual" schema elements (directives, raw SDL, etc) that the
  # `elasticgraph-apollo` library will generate on our behalf in the future. For now, this
  # includes all these schema elements just to make it as close as possible to an apollo
  # compatible schema without further changes to elasticgraph-apollo.
  #
  # https://github.com/apollographql/apollo-federation-subgraph-compatibility/blob/2.0.0/COMPATIBILITY.md#products-schema-to-be-implemented-by-library-maintainers
  ElasticGraph.define_schema do |schema|
    schema.json_schema_version 1
    schema.target_apollo_federation_version(federation_version) if federation_version

    unless federation_version == "2.0"
      schema.raw_sdl <<~EOS
        extend schema
          @link(url: "https://myspecs.dev/myCustomDirective/v1.0", import: ["@custom"])
          @composeDirective(name: "@custom")

        directive @custom on OBJECT
      EOS
    end

    # The `apollo-federation-subgraph-compatibility` project requires[^1] that each tested implementation provide
    # specific `Query` fields:
    #
    # ```graphql
    # type Query {
    #   product(id: ID!): Product
    #   deprecatedProduct(sku: String!, package: String!): DeprecatedProduct @deprecated(reason: "Use product query instead")
    # }
    # ```
    #
    # ElasticGraph automatically provides plural fields for our indexed types (e.g. `products` and `deprecatedProducts`).
    # For the Apollo tests we need to additionally provide the two fields above. This hooks into the generation of the
    # `Query` type to add the required fields.
    #
    # [^1]: https://github.com/apollographql/apollo-federation-subgraph-compatibility/blob/2.0.0/COMPATIBILITY.md#products-schema-to-be-implemented-by-library-maintainers
    schema.on_root_query_type do |type|
      type.field "product", "Product" do |f|
        f.argument "id", "ID!"
        f.resolver = :product
      end

      type.field "deprecatedProduct", "DeprecatedProduct" do |f|
        f.argument "sku", "String!"
        f.argument "package", "String!"
        f.directive "deprecated", reason: "Use product query instead"
        f.resolver = :product
      end
    end

    require_relative "../lib/product_resolver"
    schema.register_graphql_resolver :product, ProductResolver, defined_at: "./lib/product_resolver"

    schema.object_type "Product" do |t|
      t.directive "custom" unless federation_version == "2.0"
      t.apollo_key fields: "sku package"
      t.apollo_key fields: "sku variation { id }"

      t.field "id", "ID!"
      t.field "sku", "String"
      t.field "package", "String"
      t.field "variation", "ProductVariation"
      t.field "dimensions", "ProductDimension"
      t.field "createdBy", "User" do |f|
        f.apollo_provides fields: "totalProductsCreated"
      end
      t.field "notes", "String" do |f|
        f.tag_with "internal"
      end
      t.field "research", "[ProductResearch!]!" do |f|
        f.mapping type: "object"
      end

      t.index "products"
    end

    schema.object_type "DeprecatedProduct" do |t|
      t.apollo_key fields: "sku package"
      t.field "id", "ID!", indexing_only: true
      t.field "sku", "String!"
      t.field "package", "String!"
      t.field "reason", "String"
      t.field "createdBy", "User"

      t.index "deprecated_products"
    end

    schema.object_type "ProductVariation" do |t|
      t.field "id", "ID!"
    end

    schema.object_type "ProductResearch" do |t|
      t.apollo_key fields: "study { caseNumber }"
      t.field "id", "ID!", indexing_only: true
      t.field "study", "CaseStudy!"
      t.field "outcome", "String"

      t.index "product_research"
    end

    schema.object_type "CaseStudy" do |t|
      t.field "caseNumber", "ID!"
      t.field "description", "String"
    end

    schema.object_type "ProductDimension" do |t|
      t.apollo_shareable
      t.field "size", "String"
      t.field "weight", "Float"
      t.field "unit", "String" do |f|
        f.apollo_inaccessible
      end
    end

    schema.object_type "User" do |t|
      t.apollo_extends
      t.apollo_key fields: "email"
      t.field "id", "ID!", indexing_only: true

      t.field "averageProductsCreatedPerYear", "Int" do |f|
        f.apollo_requires fields: "totalProductsCreated yearsOfEmployment"
      end

      t.field "email", "ID!" do |f|
        f.apollo_external
      end

      t.field "name", "String" do |f|
        f.apollo_override from: "users"
      end

      t.field "totalProductsCreated", "Int" do |f|
        f.apollo_external
      end

      t.field "yearsOfEmployment", "Int!" do |f|
        f.apollo_external
      end

      t.index "users"
    end

    unless federation_version == "2.0"
      schema.object_type "Inventory" do |t|
        t.apollo_interface_object
        t.field "id", "ID!"
        t.field "deprecatedProducts", "[DeprecatedProduct!]!" do |f|
          f.mapping type: "object"
        end
        t.index "inventory"
      end
    end
  end
end
