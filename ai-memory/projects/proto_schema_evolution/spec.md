# Protobuf Schema Evolution

## Summary

ElasticGraph schemas change over time. Fields are renamed. Field types change. Fields and types are deleted.
JSON ingestion supports these changes. The spec `elasticgraph-indexer/spec/acceptance/schema_evolution_spec.rb`
defines the supported changes. Protobuf ingestion must pass the same spec.

Protobuf ingestion cannot copy the JSON design. The two formats differ in three important ways:

1. **JSON identifies a field by its name. Protobuf identifies a field by its number.** A renamed JSON field
   is a different field on the wire. A renamed protobuf field sends the same bytes.
2. **Each JSON event contains its schema version. A protobuf event contains no version.** The JSON indexer
   knows the contract that the publisher used. The protobuf indexer does not.
3. **Only ElasticGraph publishers use `json_schemas.yaml`. Any consumer in the organization can compile
   `schema.proto` into generated code.** A protobuf field rename does not change the wire format, but it
   breaks the build of each consumer.

This document explains how JSON evolution works today. It then explains what each difference removes or
adds for protobuf. It then gives the decisions for each point where the two formats differ.

In JSON, the versioned schemas are a **history of publisher APIs**. The indexer selects the correct version
for each event. In protobuf, `proto_field_numbers.yaml` is a **history of wire identities**. The indexer
always uses the one current contract. The history lets the dump reject a change that would make the current
contract read old bytes incorrectly.

## How JSON ingestion evolves today

Each JSON event contains a `json_schema_version`. Each `schema_artifacts:dump` writes
`json_schemas_by_version/vN.yaml`. The publisher-facing parts of an old version do not change. These parts
are the field names, the field types, and the required fields. This lets the indexer validate a v1 event as a
v1 event at any later time.

The versioned files are not fully immutable. The dump merges the *current* `ElasticGraph` metadata into each
version. An old version always contains the current `nameInIndex` for each field. The indexer validates a v1
event against the v1 publisher contract. It then writes the event to the current index destinations. The
parts that the publisher can see are frozen. The parts that only ElasticGraph can see follow the current
schema.

This table shows the JSON evolution process:

| Change | Action of the schema author | Result for a v1 event |
|---|---|---|
| Add a field | Add the field | The event is indexed. The field is absent. |
| Rename `full_name` to `name` | Increment the version. Add `f.renamed_from "full_name"`. | The event is validated as `full_name`. It is written to the current `name_in_index` of `name`. |
| Change `wins` from `JsonSafeLong` to `Int` | Increment the version. Set `name_in_index: "win_count"` so that the index mapping can change. | The event is validated as `JsonSafeLong` under v1. It is written to `win_count`. |
| Delete a field or a type | Add `deleted_field` or `deleted_type` | The event is accepted. The deleted data is dropped. |
| Publisher is ahead of the indexer | None. The indexer must deploy first. | The event is validated against the closest available version. Unexpected properties fail validation. The error is visible. |

Two properties of this design are important, because protobuf does not have them:

- **Validation per version.** A v1 publisher can send `wins: 5000000000`. This value is valid because v1
  specifies `JsonSafeLong`. A v2 publisher cannot send the same value. The indexer rejects it.
- **Name resolution per version.** The schema definition must keep `renamed_from` while any v1 publisher is
  active. The v1 file still specifies `full_name`.

## What changes with protobuf

### Field numbers replace names on the wire

Protobuf compatibility has one rule: the meaning of a field number never changes. You can add fields. You can
delete fields and reserve their numbers. You must not reuse a number. You must not change the wire type of a
number. Then a binary compiled against any version of the `.proto` can read the data of any other version.

Renames are simple on the wire. If `full_name = 2` becomes `name = 2`, old publishers and new publishers send
the same bytes. The indexer does not translate anything. `renamed_from` has no function at run time.

The risk moves to a different place. In JSON, the worst result of an incorrect schema change is a validation
error. In protobuf, a change from `int64 wins = 3` to `string wins = 3` does not fail. The decoder reads the
varint from an old publisher as a length-delimited string. The result is incorrect data or a parse error for
the full event. The dump must prevent this change. Nothing at run time can detect it.

### No schema version on the wire

We do not put a schema version in the envelope. We do not generate message classes per version. The `.proto`
exists so that warehouse loaders, other services, and publisher tools can read the same events. These
consumers follow the standard protobuf process. They compile the latest `.proto` and they depend on stable
numbers. A version field that only ElasticGraph reads would make ElasticGraph different from all other
consumers. Message classes per version would make the `.proto` non-standard for all consumers.

Myron made a note on the first draft. Some evolution cases can require a version signal. If we add one, it
must be required only for rare breaking changes. Each decision below is valid without a version signal. The
section "Alternatives considered" lists what a version signal would restore.

The missing version has these costs, compared with JSON:

- **No validation per version.** The indexer has one descriptor set and one set of GraphQL types. It cannot
  know that a publisher was permitted to send a value. A type change must be safe for *each* publisher that
  ever compiled the `.proto`. If this is not possible, the change must use a new number.
- **No detection of a publisher that is ahead of the indexer.** JSON detects this case. The closest version
  rejects unexpected properties. The protobuf decoder discards unknown fields in a known message by design.
  A new field from a new publisher disappears without an error. There is no version to compare. There is no
  older contract to use. The indexer has one `.proto`. The indexer detects only one publisher-ahead case: an
  unknown record alternative in the envelope `oneof`. This case fails. ElasticGraph always required that the
  indexer deploys before the publishers. For protobuf, this requirement is critical.
- **No non-null enforcement.** See decision 7.

### `schema.proto` is a source contract and a wire contract

JSON publishers read `json_schemas.yaml` with ElasticGraph tools. Protobuf consumers run `protoc`. They get
generated classes in Java, Go, or Kotlin. Two parts of the `.proto` can break these consumers without a change
to the wire format:

- **Names.** A rename of `full_name` to `name` does not change the bytes. But `getFullName()` does not
  compile.
- **Generated-language types.** A change from `int32` to `int64` is wire-compatible. But a Java `int` field
  becomes a `long` field.

Protobuf has two contracts. JSON has one. The design treats the two contracts differently:

- The **wire contract** is the field numbers, the wire types, the field shapes, and the referenced message
  identities. The dump enforces this contract. It rejects a change that breaks it.
- The **source contract** is the names and the generated-language types. The dump keeps this contract by
  default. A schema author can break it explicitly. Then the dump makes the requested change and prints a
  warning.

Ingestion accepts only binary protobuf encoding. The transport can wrap it in base64. We make no promise
about the protobuf JSON format or the protobuf text format. These formats encode field names.

### Comparison

| | JSON | Protobuf |
|---|---|---|
| Field identity on the wire | Name | Number |
| Version signal | `json_schema_version` on each event | None |
| Data that the dump keeps | The publisher API of each version, with the current index metadata merged in | Each number ever assigned, with its type, shape, and names |
| Validation target of the indexer | The version of the publisher | The current GraphQL type |
| Index destination | Current `name_in_index` | Current `name_in_index` |
| Public rename | New version. `renamed_from` is required while old versions are active. | Proto name does not change. `renamed_from` is required for one dump. |
| Type change | New version and `name_in_index` | Permitted only if wire-safe. Otherwise a new number. |
| Deletion | `deleted_field` or `deleted_type`. Old data is dropped. | Same declarations. The number is reserved. Old data is dropped as unknown. |
| Publisher is ahead of the indexer | Validation fails | Unknown fields are dropped without an error. Unknown record types fail. |

## Decisions

### 1. `proto_field_numbers.yaml` records the wire contract, not only the numbers

The original sidecar file stored only `field_name: number`. This keeps numbers stable. It is not sufficient to
decide if a type change is safe. A number-only entry for a deleted field does not record the old type. Each
entry is now a contract:

```yaml
messages:
  Team:
    fields:
      id:
        field_number: 1
        proto_type: string
        list_depth: 0
      name:
        field_number: 2
        proto_type: string
        list_depth: 0
        proto_name: full_name   # present only when the proto name differs from the public name
      wins:
        field_number: 3
        proto_type: int64
        list_depth: 0
    next_number: 4
```

The sidecar file is the protobuf equivalent of `json_schemas_by_version/`. You must not delete it after
publishers exist. The two differ in content. JSON keeps the full historical schemas because it must repeat
the validation of each version. Protobuf keeps only the data that the dump needs to reject an unsafe change.
The run time does not read the sidecar file. Index destinations are not in the sidecar file. They are also
not in the public `json_schemas.yaml`.

The next dump migrates number-only entries from older sidecar files. It uses the current schema. This works
for fields that still exist. It cannot recover the historical type of a deleted field. These fields stay as
tombstones. You cannot restore them until you record the original `proto_type` by hand. Dump a legacy schema
before you change it.

### 2. Public names change. Proto names do not change.

In JSON, a rename creates a new version. The old name stays in `v1.yaml`. In protobuf, the old name stays in
the `.proto`. This schema definition renames the field:

```ruby
t.field "name", "String!", name_in_index: "full_name" do |f|
  f.renamed_from "full_name"
end
```

The generated message still contains:

```protobuf
  // Public GraphQL field: name.
  string full_name = 2;
```

The dump records `proto_name: full_name` under the public key `name` in the sidecar file. The run-time
metadata maps `full_name` to `name`. This happens before the record reaches derived indexing, routing, and
rollover. These stages see the same record that a JSON event produces. The comment is for people who read
the `.proto`. Bazel descriptor sets drop the comment. Nothing at run time uses it.

We keep the old name because a rename is free on the wire but expensive in source. Each consumer that
recompiles the `.proto` would break. The change was to the GraphQL API, not to the event contract. The same
reason applies to message names, enum names, and enum value names (decision 3).

This design has one advantage over JSON. `renamed_from` must survive only one dump. The sidecar file keeps
the link. You can remove the declaration after the dump. The `.proto` does not change. A project that also
ingests JSON must keep `renamed_from` while old JSON versions are active. This is the JSON mechanism, not the
protobuf mechanism.

A project can change the proto name to the public name. This breaks the source contract. The project must
request it explicitly:

```ruby
t.field "name", "String!", name_in_index: "full_name" do |f|
  f.renamed_from "full_name"
  f.protobuf name: "name"
end
```

The field keeps number 2. Values from old publishers continue to arrive during the rename. The dump prints:

```
Source-breaking protobuf rename: `Team.full_name` becomes `name`; its number is unchanged.
```

### 3. Message names, enum names, and enum value names do not change

Apply `t.renamed_from "Address"` to a type that is now named `PostalAddress`. The `.proto` keeps
`message Address`. It keeps each field number. It keeps the envelope alternatives and the union `oneof`
alternatives that refer to the message. This also corrects a defect in the number-only sidecar file. A renamed
type started its numbers from 1. Old publishers and new publishers could then send different fields under the
same number.

Enum types and enum values accept `renamed_from` in the protobuf extension for the same reason. A type-level
`protobuf name:` is out of scope. No ElasticGraph feature must rename a message. A message rename breaks the
source contract for each consumer.

### 4. Both formats write to the current `name_in_index`. Only the validation differs.

The first draft said that a JSON v1 event continues to write to the old index field after a `name_in_index`
change. This was not correct. The dump merges the current `nameInIndex` into each version. JSON and protobuf
have the same behavior here. Each event from each publisher writes to the current destination. Documents that
were indexed before the change need a backfill in both formats.

The difference is the validation target. JSON validates a value against the version of the publisher.
Protobuf validates a value against the current GraphQL type. Protobuf has no other type. Decision 5 makes
this safe.

### 5. In-place type changes are limited to lossless integer widenings. All other changes rotate.

In JSON, a change of `wins` from `JsonSafeLong` to `Int` needs a new version and `name_in_index: "win_count"`.
The indexer validates v1 events as `JsonSafeLong`. It validates v2 events as `Int`. It writes both to
`win_count`.

Protobuf cannot do this. Both publishers send `wins = 3` as a varint. The indexer has one descriptor to
decode it. If the dump changed the `.proto` to `int32 wins = 3`, the decoder would truncate the value
`5000000000` from a v1 publisher to 32 bits. This happens before validation. The dump compares the default
proto type of the requested type with the sidecar file. It applies this table:

| Stored wire type | Requested type | Result |
|---|---|---|
| Same type and list depth | Same | No change |
| `int32`, `sint32`, or `uint32` | The 64-bit equivalent | The `.proto` widens. The dump prints a source-breaking warning. |
| `int64`, `sint64`, or `uint64` | The 32-bit equivalent | The `.proto` keeps the wider type. Ingestion enforces the GraphQL range. |
| Any other type | Any other type | The dump fails. Rotate the field (see below). |

**Widening** (`Int` to `JsonSafeLong`) is the common case. Protobuf permits it. The wider type can hold each
value from an old publisher. The change breaks the source contract for typed languages. The dump prints:

```
Source-breaking protobuf widening: `Team.wins` changes from int32 to int64. Upgrade downstream readers before publishing values outside the old range.
```

**Narrowing** (`JsonSafeLong` to `Int`) keeps `int64` on the wire. Ingestion enforces the `Int` range. The
indexer rejects the value `5000000000` from a v1 publisher with a validation error. It does not truncate the
value. This check runs when record validation is sampled out. Sampling skips expensive validation of correct
events. It does not accept values that the wire type would corrupt. The check also runs inside nested lists.
The `.proto` annotates the field so that consumers are not misled by the wide type:

```protobuf
  // Accepted range: -2147483648 to 2147483647. Values outside this range are rejected.
  int64 wins = 3;
```

**All other changes** fail the dump. We did not adopt the full protobuf compatibility groups. In those
groups, `int32`, `int64`, `uint32`, `uint64`, and `bool` share a wire type. `string` and `bytes` share a wire
type. These groups define what parses. They do not define what keeps its meaning. `int32` to `uint32`
changes negative values. `int64` to `bool` merges values. `bytes` to `string` accepts invalid UTF-8. The
three widenings above are the only changes that keep the meaning of each historical value.

```
Incompatible protobuf change for `Team.wins`: int64 (list depth 0) cannot carry string (list depth 0). Use `f.protobuf name: "wins_new"` to rotate to a fresh number.
```

**Rotation** is the protobuf equivalent of a JSON version increment with `name_in_index`:

```ruby
t.field "wins", "String", name_in_index: "wins_text" do |f|
  f.protobuf name: "wins_str"
end
```

The new proto name gets a new number. The old number is reserved. The old contract moves to `retired_fields`
in the sidecar file. An incompatible field can never reuse it.

```protobuf
message Team {
  string id = 1;
  // Public GraphQL field: name.
  string full_name = 2;
  // Public GraphQL field: wins.
  string wins_str = 4;
  reserved 3; // Previously used by wins.
  // Next field number: 5
}
```

Values from old publishers arrive on number 3. The indexer discards them as unknown fields. This is the same
result as a deleted field. It is the correct result. There is no way to convert an old `int64` value into
the new `String` field. The GraphQL field is still named `wins`. This is the purpose of rotation. Without
rotation, the only way to change a type would be to rename the public field. A wire constraint would then
control the GraphQL API.

`f.protobuf name:` on a field with the same type is a rename (decision 2). `f.protobuf name:` on a field with a
compatible widened type is also a rename. Neither is a rotation. The dump knows the stored type and the
requested type. It can tell the two cases apart.

### 6. Deletions are explicit in both formats. Protobuf reserves the number permanently.

To drop a field or a type, you must add `deleted_field` or `deleted_type`. This is the same as JSON. The
artifacts differ. JSON keeps the field in old versions and drops the data at ingestion. Protobuf reserves the
number in the `.proto` and in the sidecar file. The indexer drops values from old publishers as unknown fields.
A new field cannot use a reserved proto name. Use a different name, or restore the original field. A restored
field reclaims its number if the type is compatible.

A removed enum value also reserves its number. Proto3 enums are open. A retired value from an old publisher
decodes as an integer. The converter maps a known retired number to `nil`. This is the same result as a
reserved field. The converter fails on a number that it has never seen. The Ruby decoder exposes the integer
under proto2 and under proto3. The behavior is the same under both syntaxes here. Other proto2 consumers can
see the value as absent.

**Events for deleted indexed types** are ignored in both formats. JSON already does this. In envelope format,
the record `oneof` alternative for the deleted type is a reserved envelope number. The decoder cannot see it.
The Ruby protobuf library has no unknown-fields accessor. The decoder scans the envelope bytes with a bounded
wire-format reader. The reader validates the tags, the wire types, and the lengths. The decoder ignores the
event only when it finds exactly one reserved alternative and nothing else unexpected. An ambiguous envelope
fails. A malformed envelope fails. In raw format, a transport `eg_type` that names a deleted type is ignored in
the same way.

### 7. Ingestion does not enforce non-null fields

JSON enforces `required` per version. A field that v3 adds as non-null is required from v3 publishers. It is
not required from v1 publishers. Protobuf cannot make this distinction. An old publisher that omits a new
field sends the same bytes as a new publisher that forgets the field. Generated fields are `optional` in both
syntaxes. The indexer knows if a field is present. General non-null enforcement is deferred.

Enforcement is safe for one group of fields: fields that were non-null when the message was first generated.
No publisher could compile a version of the message without them. Fields that were added later can never be
enforced without a version signal. Operational requirements still apply. The envelope identity and the
envelope version are required. Rollover needs its timestamp. Routing rules apply.

### 8. Run-time metadata contains only the facts that descriptors cannot express

For JSON, the run-time metadata is the versioned schemas. For protobuf, the record structure comes from the
descriptor set. The run-time metadata is a small set of overrides:

- Private `name_in_index` values
- Proto-to-public name mappings, where the names differ
- Scalars with ingestion rules that differ from their wire type. An `Int` carried by a retained `int64` must
  not get the default `int64` ingestion behavior.
- Enum value names that casing cannot recover
- Valid time zones
- Retired enum numbers
- Deleted type identities
- The reserved envelope numbers from decision 6

## Alternatives considered

- **A schema version in the envelope.** This is the only alternative that restores validation per version,
  non-null enforcement, and publisher-ahead detection. We rejected it for now. It makes the `.proto`
  ElasticGraph-specific for each other consumer. If we add it later, it must be required only for rare
  breaking changes. The no-version path must stay the default.
- **A frozen `name_in_index` per field number.** An earlier draft kept retired numbers as deprecated fields.
  They would write to their old index destination. This would match JSON document for document. We dropped
  it when we confirmed that JSON does not do this. Both formats write to the current destination.
- **The protobuf compatibility groups.** We rejected them for the explicit widening table. See decision 5.
- **A compatibility check against the previous committed `schema.proto`**, as `buf breaking` does, instead
  of types in the sidecar file. This would avoid a copy of `proto_type`. But the documentation says that you
  can delete and regenerate the schema artifacts. The sidecar file is already the one file that you must
  keep. The history stays in the sidecar file to keep this rule simple.
- **Structure in proto comments or custom options.** Bazel descriptor sets drop comments by default.
  `name_in_index` must stay private. Custom options add an import for each publisher.
- **A change history per number, like `json_schemas_by_version`.** Without a version signal, an event cannot
  identify its entry. The indexer could not select one.

## Expected behavior in `schema_evolution_spec.rb`

| Scenario | JSON | Protobuf |
|---|---|---|
| Field added | Old events are indexed. The field is absent. | Same |
| Routing and rollover fields renamed. `name_in_index` kept. | Both versions are indexed. | Same. The number and the proto name do not change. |
| Field deleted | Old values are dropped. | Same. The number is reserved. The value is dropped as unknown. |
| Nested type renamed | Both versions are indexed. | Same. The message name and the numbers do not change. |
| `JsonSafeLong` to `Int` with `name_in_index: "win_count"` | v1 is validated as `JsonSafeLong`. v2 is validated as `Int`. Both write `win_count`. | Both write `win_count`. `int64` stays on the wire. The `Int` range is enforced for all. |
| Public field renamed. `name_in_index` kept. | Both versions write the same index field. | Same. The proto field keeps its old name. |
| Embedded type dropped | Old data is dropped. | Same |
| Indexed type dropped | Old events are ignored. | Same, in envelope format and in raw format |
| Incompatible type change (`Int` to `String`) | Version increment and `name_in_index` | The dump fails. `f.protobuf name:` rotates to a new number. |
| `renamed_from` removed after a dump | Old versions still need it. | The contract does not change. |
| Enum value removed | The old version still validates it. | The retired number decodes to `nil`. |

The spec asserts the indexed documents. It does not assert only the absence of errors. Dropped data or
truncated data would otherwise pass. The protobuf variant compiles each schema snapshot into its own
`DescriptorPool`. It encodes old events with the classes of that snapshot. The test sends the exact bytes
that an old publisher would send. The indexer runs on the latest artifacts only.

## Open questions

- **Escape from a retained wider type.** After a `JsonSafeLong` to `Int` narrowing, the `.proto` keeps
  `int64` permanently. This applies even if the wide type existed only during prototyping. The only reset
  today is to delete the sidecar file. This is safe only before any publisher exists. We probably want an
  explicit override with a warning, for example `f.protobuf type: "int32"`. Teams can use it when they know
  that no wide values were published.
- **When to add a version signal.** See the first alternative above. The probable trigger is the first real
  schema that must enforce a non-null field added after the message was first published.

## Status

#1406 implements this design. #1412 runs the indexer acceptance specs and integration specs against both
ingestion formats. #1388 adds the protobuf indexer wrapper and the end-to-end integration tests on top.
