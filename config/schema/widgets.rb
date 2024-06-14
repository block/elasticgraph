# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# The types in this schema file are used by most tests.
ElasticGraph.define_schema do |schema|
  schema.enum_type "Color" do |e|
    e.values %w[RED BLUE GREEN]
  end

  schema.enum_type "Size" do |e|
    e.values %w[SMALL MEDIUM LARGE]
  end

  schema.enum_type "Material" do |e|
    e.values %w[ALLOY CARBON_FIBER]
  end

  schema.object_type "WidgetOptions" do |t|
    t.field "size", "Size"
    # `the_size` is defined with a different `name_in_index` so we can demonstrate grouping works
    # when a selected `group_by` option has a different name in the index vs GraphQL.
    t.field "the_size", "Size", name_in_index: "the_sighs"
    t.field "color", "Color"
    t.field "is_draft", "Boolean"
  end

  schema.object_type "Person" do |t|
    t.implements "NamedInventor"
    t.field "name", "String"
    t.field "nationality", "String"
  end

  schema.object_type "Company" do |t|
    t.implements "NamedInventor"
    t.field "name", "String"
    t.field "stock_ticker", "String"
  end

  schema.union_type "Inventor" do |t|
    t.subtypes "Person", "Company"
  end

  # Embedded interface type.
  schema.interface_type "NamedInventor" do |t|
    t.field "name", "String"
  end

  # Indexed interfae type.
  schema.interface_type "NamedEntity" do |t|
    t.root_query_fields plural: "named_entities"
    t.field "id", "ID!"
    t.field "name", "String"
  end

  # Note: it is important that no list field is added to this `Money` type. We are using it as an example
  # of a `nested` list field with no list fields of its own in the `teams.rb` schema.
  schema.object_type "Money" do |t|
    t.field "currency", "String!"
    t.field "amount_cents", "Int"
  end

  schema.object_type "Position" do |t|
    t.field "x", "Float!"
    t.field "y", "Float!"
  end

  schema.object_type "Widget" do |t|
    t.root_query_fields plural: "widgets"
    t.implements "NamedEntity"
    t.field "id", "ID!"

    # Here we use an alternate name for this field since it's the routing field and want to verify
    # that `name_in_index` works correctly on routing fields.
    t.field "workspace_id", "ID", name_in_index: "workspace_id2"

    # It's a bit funny we have both `amount_cents` and `cost` but it's nice to be able to test
    # aggregations on both a root numeric field and on a nested one, so we are keeping both here.
    t.field "amount_cents", "Int!"
    # Note: we are naming this field differently so we can demonstrate that filtering/aggregating
    # on a field that is named differently in the index works.
    t.field "amount_cents2", "Int!", name_in_index: "amount_cents", graphql_only: true
    t.field "cost", "Money"
    t.field "cost_currency_unit", "String"
    t.field "cost_currency_name", "String"
    t.field "cost_currency_symbol", "String"
    t.field "cost_currency_primary_continent", "String"
    t.field "cost_currency_introduced_on", "Date"
    t.field "name", "String"
    t.field "name_text", "String" do |f|
      f.mapping type: "text"
    end
    t.field "created_at", "DateTime!"
    # `created_at2` is defined with a different `name_in_index` so we can demonstrate grouping works
    # when a selected grouping field has a different name in the index vs GraphQL.
    t.field "created_at2", "DateTime!", name_in_index: "created_at", graphql_only: true
    t.field "created_at_time_of_day", "LocalTime"
    t.field "created_on", "Date"
    t.field "release_timestamps", "[DateTime!]!", singular: "release_timestamp"
    t.field "release_dates", "[Date!]!", singular: "release_date"
    t.relates_to_many "components", "Component", via: "component_ids", dir: :out, singular: "component"
    t.field "options", "WidgetOptions"

    # Demonstrate using `name_in_index` with a graphql-only embedded field.
    t.field "size", "Size", name_in_index: "options.size", graphql_only: true

    # `the_options` is defined with a different `name_in_index` so we can demonstrate grouping works when a parent field
    # of a selected `group_by` option has a different name in the index vs GraphQL.
    t.field "the_options", "WidgetOptions", name_in_index: "the_opts"
    t.field "inventor", "Inventor"
    t.field "named_inventor", "NamedInventor"
    t.field "weight_in_ng_str", "LongString!" # Weight in nanograms, to exercise Long support.
    t.field "weight_in_ng", "JsonSafeLong!" # Weight in nanograms, to exercise Long support.
    t.field "tags", "[String!]!", sortable: false, singular: "tag"
    t.field "amounts", "[Int!]!", sortable: false do |f|
      f.mapping index: false
    end
    t.field "fees", "[Money!]!", sortable: false do |f|
      f.mapping type: "object"
    end
    t.field "metadata", "Untyped"

    # TODO: change `widget.` in these field paths to `widgets.` when we can support `sourced_from` with that.
    t.relates_to_one "workspace", "WidgetWorkspace", via: "widget.id", dir: :in do |rel|
      rel.equivalent_field "id", locally_named: "workspace_id"
      rel.equivalent_field "widget.created_at", locally_named: "created_at"
    end

    t.field "workspace_name", "String" do |f|
      f.sourced_from "workspace", "name"
    end

    # Customize the index so we can demonstrate that index customization works.
    # Also, to demonstrate that custom shard routing works correctly, we need multiple shards.
    # That way, our documents wind up on multiple shards and we can demonstrate that our
    # queries are directly routed to the correct shards.
    t.index "widgets", number_of_shards: 3 do |i|
      i.rollover :yearly, "created_at"
      i.route_with "workspace_id"
      i.default_sort "created_at", :desc
    end

    t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency", route_with: "cost_currency_primary_continent", rollover_with: "cost_currency_introduced_on" do |derive|
      derive.immutable_value "name", from: "cost_currency_name"
      derive.immutable_value "introduced_on", from: "cost_currency_introduced_on"
      derive.immutable_value "primary_continent", from: "cost_currency_primary_continent"
      derive.immutable_value "details.unit", from: "cost_currency_unit", nullable: false
      derive.immutable_value "details.symbol", from: "cost_currency_symbol", can_change_from_null: true

      # named `widget_names2` to match `name_in_index` of `WidgetCurrency.widget_names`
      # Note: `sourced_from` handles `name_in_index` better and should avoid the need to use the
      # `name_in_index` here.
      derive.append_only_set "widget_names2", from: "name"

      derive.append_only_set "widget_options.colors", from: "options.color"
      derive.append_only_set "widget_options.sizes", from: "options.size"
      derive.append_only_set "widget_tags", from: "tags"
      derive.append_only_set "widget_fee_currencies", from: "fees.currency"
      derive.max_value "nested_fields.max_widget_cost", from: "cost.amount_cents"
      derive.min_value "oldest_widget_created_at", from: "created_at"
    end
  end

  schema.object_type "WidgetOptionSets" do |t|
    t.field "sizes", "[Size!]!"
    t.field "colors", "[Color!]!"
  end

  schema.object_type "WidgetCurrencyNestedFields" do |t|
    t.field "max_widget_cost", "Int"
  end

  schema.object_type "CurrencyDetails" do |t|
    t.field "unit", "String"
    t.field "symbol", "String"
  end

  schema.object_type "WidgetCurrency" do |t|
    t.root_query_fields plural: "widget_currencies"
    t.field "id", "ID!"
    t.field "name", "String"
    t.field "introduced_on", "Date"
    t.field "primary_continent", "String"
    t.field "details", "CurrencyDetails"
    t.paginated_collection_field "widget_names", "String", name_in_index: "widget_names2", singular: "widget_name"
    t.field "widget_tags", "[String!]!"
    t.field "widget_fee_currencies", "[String!]!"
    t.field "widget_options", "WidgetOptionSets"
    t.field "nested_fields", "WidgetCurrencyNestedFields"
    t.field "oldest_widget_created_at", "DateTime"
    t.index "widget_currencies" do |i|
      i.rollover :yearly, "introduced_on"
      i.route_with "primary_continent"
    end
  end

  schema.object_type "WidgetWorkspace" do |t|
    t.root_query_fields plural: "widget_workspaces"
    t.field "id", "ID!"
    t.field "name", "String"

    # TODO: replace `widget` with `widgets` when we can support `sourced_from` with that.
    t.field "widget", "WorkspaceWidget"
    # t.field "widgets", "[WorkspaceWidget!]!"

    t.index "widget_workspaces"
  end

  schema.object_type "WorkspaceWidget" do |t|
    t.field "id", "ID!"
    t.field "created_at", "DateTime"
  end

  schema.object_type "Component" do |t|
    t.root_query_fields plural: "components"
    t.implements "NamedEntity"
    t.field "id", "ID!"
    t.field "name", "String"
    t.field "created_at", "DateTime!"
    t.field "position", "Position!"
    t.field "tags", "[String!]!"

    t.field "widget_name", "String" do |f|
      f.sourced_from "widget", "name"
    end

    t.field "widget_tags", "[String!]" do |f|
      f.sourced_from "widget", "tags"
    end

    # We use `name_in_index` here to demonstrate that a `sourced_from` field can flow into an alternately named field.
    t.field "widget_workspace_id", "ID", name_in_index: "widget_workspace_id3" do |f|
      f.sourced_from "widget", "workspace_id"
    end

    t.field "widget_size", "Size" do |f|
      # Here we're demonstrating usage on a nested field, and on fields which use an alternative `name_in_index`.
      f.sourced_from "widget", "the_options.the_size"
    end

    # `Money` is an object type, so this is defined to demonstrate that denormalizing object values works.
    t.field "widget_cost", "Money" do |f|
      f.sourced_from "widget", "cost"
    end

    t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in
    t.relates_to_one "dollar_widget", "Widget", via: "component_ids", dir: :in do |rel|
      rel.additional_filter "cost" => {"amount_cents" => {"equal_to_any_of" => [100]}}
    end
    # In practice, there is one widget to many components. But to exercise an edge case it is useful to have a
    # many-to-many as well, so here we expose a list even though it will only ever be a list of 1.
    t.relates_to_many "widgets", "Widget", via: "component_ids", dir: :in, singular: "widget"
    t.relates_to_many "parts", "Part", via: "part_ids", dir: :out, singular: "part"

    t.index "components" do |i|
      i.default_sort "created_at", :desc
    end
  end

  schema.object_type "MechanicalPart" do |t|
    t.root_query_fields plural: "mechanical_parts"
    t.implements "NamedEntity"
    t.field "id", "ID!"
    t.field "name", "String"
    t.field "created_at", "DateTime!"
    t.field "material", "Material"
    t.relates_to_many "components", "Component", via: "part_ids", dir: :in, singular: "component"
    t.relates_to_one "manufacturer", "Manufacturer", via: "manufacturer_id", dir: :out

    t.index "mechanical_parts" do |i|
      i.default_sort "created_at", :desc
    end
  end

  schema.object_type "ElectricalPart" do |t|
    t.root_query_fields plural: "electrical_parts"
    t.implements "NamedEntity"
    t.field "id", "ID!"
    t.field "name", "String"
    t.field "created_at", "DateTime!"
    t.field "voltage", "Int!"
    t.relates_to_many "components", "Component", via: "part_ids", dir: :in, singular: "component"
    t.relates_to_one "manufacturer", "Manufacturer", via: "manufacturer_id", dir: :out

    t.index "electrical_parts" do |i|
      i.default_sort "created_at", :desc
    end
  end

  schema.union_type "Part" do |t|
    t.subtypes "MechanicalPart", "ElectricalPart"
  end

  # Note: `Manufacturer` is used in our tests as an example of an indexed type that has no list fields, so we should
  # not add any list fields to this type in the future.
  schema.object_type "Manufacturer" do |t|
    t.root_query_fields plural: "manufacturers"
    t.implements "NamedEntity"
    t.field "id", "ID!"
    t.field "name", "String"
    t.field "created_at", "DateTime!"
    t.relates_to_many "manufactured_parts", "Part", via: "manufacturer_id", dir: :in, singular: "manufactured_part"
    t.relates_to_one "address", "Address", via: "manufacturer_id", dir: :in

    t.index "manufacturers" do |i|
      i.default_sort "created_at", :desc
    end
  end

  schema.object_type "AddressTimestamps" do |t|
    t.field "created_at", "DateTime"
  end

  schema.object_type "GeoShape" do |t|
    t.field "type", "String"
    t.field "coordinates", "[Float!]!"

    # Here we are using a custom mapping type on an object type so we can verify that the schema
    # artifact generation works as expected in this case.
    #
    # Note: `geo_shape` is one of the few custom mapping types available on both OpenSearch and Elasticsearch,
    # which is why we've chosen it here.
    # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/mapping-types.html
    # https://opensearch.org/docs/latest/field-types/supported-field-types/index/
    t.mapping type: "geo_shape"
  end

  schema.object_type "Address" do |t|
    t.root_query_fields plural: "addresses"
    # We use `indexing_only: true` here to verify that `id` can be an indexing-only field.
    t.field "id", "ID!", indexing_only: true

    t.field "full_address", "String!"
    t.field "timestamps", "AddressTimestamps"
    t.field "geo_location", "GeoLocation"

    # Not used by anything, but defined so we can test how a list-of-objects-with-custom-mapping
    # works in our schema generation.
    t.field "shapes", "[GeoShape!]!"

    t.relates_to_one "manufacturer", "Manufacturer", via: "manufacturer_id", dir: :out

    t.index "addresses" do |i|
      # We don't yet support a default sort of a nested field so we use id here instead of `timestamps.created_at`.
      i.default_sort "id", :desc
    end
  end

  # Defined so we can exercise having a union type with a subtype that's uses a rollover index.
  schema.union_type "WidgetOrAddress" do |t|
    t.subtypes "Widget", "Address"
    t.root_query_fields plural: "widgets_or_addresses"
  end
end
