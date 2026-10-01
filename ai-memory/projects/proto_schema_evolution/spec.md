## Context

JSON ingestion evolves safely because events name the JSON schema version they were published with.
Historical JSON schemas retain publisher-facing names and validation rules, while artifact dumping merges
current indexing metadata into those schemas. In particular, both historical and current JSON events write
to the current `name_in_index`; a historical schema is not an immutable snapshot of index destinations.

Protobuf events carry no schema version. The indexer uses the latest descriptor set, and fields are matched
by number rather than name. `proto_field_numbers.yaml` is cumulative contract history, not a set of publisher
schema versions. It records the identities, types, shapes, and numbers needed to evolve that contract safely.

The forcing function is `elasticgraph-indexer/spec/acceptance/schema_evolution_spec.rb`, run against both JSON
and protobuf ingestion. Its assertions must check indexed values and destinations, not just successful processing.

## Constraint: no schema version on the protobuf side

The generated `schema.proto` is a single, unversioned contract. Neither envelopes nor records carry a schema
version, and the runtime does not select a historical descriptor or version-specific message class.

The `.proto` can have consumers other than ElasticGraph: warehouse loaders, other services, and publishers'
own tooling. Names and numbers stay stable by default so those consumers can recompile independently. The
compatibility guarantee is directional: bytes from an old publisher remain readable without truncation by the
current indexer, subject to current validation and intentional removal of retired data. It does not promise
that every old reader can represent every value a newer publisher can send after an integer widening.

Costs of this constraint:

- The indexer cannot distinguish an old publisher legitimately omitting a new non-null field from a new
  publisher forgetting it. General GraphQL non-null enforcement is therefore deferred.
- Type and field-shape changes must preserve historical values or use a new number. JSON can instead retain
  historical publisher validation under each version.
- Deploying the indexer before publishers is recommended for both formats. An unknown top-level protobuf
  record alternative fails; added unknown fields within a known message are ordinarily discarded. There is
  no reliable general publisher-ahead detection without a version signal. JSON's closest-available-version
  fallback likewise cannot validate a newer publisher contract that has not been deployed.

A version signal remains a possible future extension if stricter presence checks or publisher-ahead detection
become requirements; it is not part of this implementation.

## Two contracts, not one

- **Wire contract:** field numbers, scalar interpretation, referenced message/enum identity, and field shape
  (singular/repeated and nested-list depth). Sharing a wire encoding is not enough: unrelated messages and
  strings/bytes can all be length-delimited but are not interchangeable. The dump rejects unsafe changes.
- **Source contract:** message, field, enum, and enum-value names, and generated-language field types. Public
  GraphQL renames do not implicitly change these. An explicit protobuf field rename or integer widening can
  break recompiled consumer source code even when old binary payloads remain readable; the dump reports it.

Only binary protobuf encoding is accepted, optionally base64-encoded by the transport. Protobuf JSON/text
name compatibility is not promised.

## Decisions

1. **Numbers are never reassigned to unrelated wire identities.** The sidecar records each field's
   `field_number`, `proto_type`, and `list_depth`, plus `proto_name` when it differs from its public name.
   Message and enum entries likewise retain their stable protobuf names. Deleted entries remain as tombstones;
   rotated field incarnations remain separately in `retired_fields`, keyed by their retired wire name. The
   allocation cursor advances beyond every active and retired number, and gaps are never filled.

   Illustrative sidecar shape after an incompatible rotation of `wins`:

   ```yaml
   messages:
     Team:
       fields:
         wins:
           field_number: 4
           proto_type: string
           list_depth: 0
           proto_name: wins_str
       retired_fields:
         wins:
           field_number: 3
           proto_type: int64
           list_depth: 0
           deleted: true
       next_number: 5
   ```

   Index destinations are private runtime metadata, never part of this public wire-contract history.
   Legacy integer-only entries can seed known current fields, but cannot prove the type of a field already
   removed. Historical contracts must be supplied explicitly when unavailable; the dump must not guess a
   retired type or silently reuse an unproven contract. Deleting the sidecar resets compatibility history and
   is allowed only while prototyping, before any generated contract has serialized data or gained consumers.

2. **The GraphQL schema evolves independently of the wire contract.** Public renames, compatible type
   changes, and `name_in_index` changes do not require old publishers to change their bytes. The indexer maps
   them to current public names, writes to the current index destination, and applies current protobuf
   ingestion rules.

   Both JSON and protobuf write historical events to the current `name_in_index`. Their important difference
   is validation: JSON can validate a historical publisher's wider type, while protobuf validates against the
   current GraphQL scalar. Documents indexed before a destination change need a backfill under either format.

3. **In-place type changes are an explicit directional table, not generic compatibility groups.**

   | Stored wire type | Requested type | Emitted type |
   |---|---|---|
   | Exact same type and shape | Same | Stored type |
   | `int32` | `int64` | `int64` |
   | `sint32` | `sint64` | `sint64` |
   | `uint32` | `uint64` | `uint64` |
   | `int64` | `int32` | Retain `int64` |
   | `sint64` | `sint32` | Retain `sint64` |
   | `uint64` | `uint32` | Retain `uint64` |
   | Any other type or shape change | Different | Require rotation (decision 4) |

   No signed/unsigned or Boolean reinterpretation, string/bytes change, unrelated named-message change,
   fixed-width reinterpretation, or singular/repeated/nested-depth change is inferred to be safe.

   Widening preserves old-publisher values in current readers, but new values outside the old range require
   downstream reader upgrades. Widening is reported as a source-breaking change. Narrowing the requested
   GraphQL scalar does not narrow the wire type: doing so would truncate historical values before validation.
   Fields carried by a wider retained wire type document the accepted current scalar range. Evolution-critical
   range checks are mandatory, including within nested lists, even when sampling skips general record
   validation. Out-of-range values fail rather than being truncated or indexed without checking.

4. **Incompatible type or shape changes rotate the field with a new proto name.**

   ```ruby
   t.field "wins", "String" do |f|
     f.protobuf name: "wins_str"
   end
   ```

   A fresh, non-colliding name claims a fresh number; the old incarnation and contract become retired and its
   number is reserved. Old publishers' values on that retired number are intentionally discarded. The dump's
   incompatibility error points to this remedy. This permits preserving the GraphQL field name without
   reinterpreting its historical bytes.

   An explicit `f.protobuf name:` with unchanged or compatible type and shape is a source rename, not a
   rotation: it keeps the number and reports the source break. Active and retired names/numbers are checked
   for collisions. Restoring a retired incarnation is allowed only when its contract is compatible and its
   original identity is unambiguous; it must not silently resurrect unrelated data.

5. **Proto field names do not follow GraphQL renames.** After `full_name` becomes `name` using
   `renamed_from`, the protobuf field stays `full_name = N`. Runtime overrides map it to the current public
   name before derived indexing, routing, and rollover consume the record.

   The first dump migrates the sidecar's public association and persists the old protobuf name. Later removing
   `renamed_from` does not change the protobuf contract. Projects also using JSON must retain their rename
   declarations while historical JSON schemas still require them. A project can explicitly request a source
   rename with `f.protobuf name:`; the number stays fixed unless the change requires rotation.

   Generated nested-list wrappers derive from the retained protobuf field name, not the GraphQL field name.

6. **Message, enum, and enum-value names retain their wire identities across public renames.** Type
   renames migrate the public association while keeping the protobuf name and every field/value number.
   Envelope and abstract-type `oneof` alternatives, enum prefixes, and references use those stable names.
   The protobuf extension adds `renamed_from` on enum types and enum values; these APIs were not already
   supplied by the core enum DSL. Type-level `protobuf name:` is out of scope.

7. **Field and type removals are explicit and durable.** Dropping a generated field or type requires
   `deleted_field` / `deleted_type`. Deletion state persists after a successful dump, so declarations can later
   be removed without erasing the tombstone. Removing an indexed/source role or an abstract subtype is distinct
   from deleting the underlying schema type: envelope/oneof alternatives retire, but a still-defined type must
   not be falsely classified as deleted.

   Reserved names cannot be claimed by unrelated new fields; choose another proto name or explicitly restore
   the compatible original. Removed enum values retain reserved numbers. For proto3 open enums, known retired
   numbers convert to `nil`, while genuinely unknown numbers fail validation. The current Ruby protobuf
   decoder exposes unknown numbers for both generated syntaxes, so these rules apply to proto2 and proto3,
   including `nil` slots in repeated fields. Other proto2 consumers can apply closed-enum semantics instead:
   singular retired values become absent and repeated retired elements disappear. Do not assume every
   downstream consumer preserves those elements.

8. **Events for deleted indexed types are ignored in envelope and raw transports.** Runtime metadata
   includes deleted raw type identities/aliases and reserved envelope-number ownership. Raw metadata naming a
   known deleted type is ignored instead of attempting to resolve a missing descriptor.

   A deleted envelope record is ignored only when scanning the original bytes establishes one unambiguous
   deleted record alternative. Multiple known, deleted, or unsupported alternatives are not silently ignored;
   malformed encodings and unsupported record tags fail. An envelope with no record and no known deleted
   alternative fails. A reserved envelope number for a still-defined but no-longer-ingestible type is not
   evidence of deletion.

   Ruby's protobuf API exposes no unknown-field accessor. Use a bounded wire-field scanner that validates tags,
   wire types, lengths, and varints; do not search for a tag byte substring or rely on re-encoding preserving
   alternative order. Ordinary unknown fields within a known record remain protobuf's usual partial-decoding
   fallback. When the last ingestible type is deleted, retain the minimal batch/envelope descriptor and
   tombstone metadata so old events can still be classified.

9. **General GraphQL non-null constraints are not enforced at ingestion.** Generated singular fields
   are `optional` in both syntaxes, preserving absence versus explicit zero, false, or empty string. Proto2
   technically permits `required`, but this generator intentionally does not emit it. A versionless indexer
   cannot safely require a newly added field from every historical publisher.

   This does not waive operational requirements: envelope identity/version are required, and rollover still
   needs its configured timestamp. Shared routing rules still apply, and a null derived-document identifier
   can produce no derived operation. Nullability is not a guarantee that every missing record value is
   operationally usable. Presence enforcement for fields required since a message's inception remains deferred.

10. **Runtime metadata holds only facts descriptors cannot express.** These include private index
    destinations, proto-to-public type/field mappings where they differ, effective-wire scalar overrides,
    enum-name casing/rename overrides, known retired enum numbers, valid time zones, deleted type identities,
    and reserved envelope ownership. Scalar overrides compare against the *retained effective wire type*:
    current `Int` carried by `int64` must not inherit that wire type's default `LongString` ingestion behavior.

    Metadata and generated definitions must use the same reconciled contract, independent of which artifact
    accessor is evaluated first.

## Rejected alternatives

- **A schema version or versioned message classes:** not required by this contract; remains open for future
  stricter presence/version detection.
- **Freezing historical `name_in_index` per number:** neither format needs historical index destinations;
  current queries read current destinations, and old documents still require backfilling.
- **Generic protobuf compatibility groups:** wire-parsable changes can reinterpret signs/Booleans, truncate
  values, or accept invalid UTF-8. Explicit directional conversions are more narrowly justified.
- **Per-version runtime history:** without a version signal the indexer cannot select a historical entry.
  Cumulative identity/contract history is still necessary to reject unsafe dumps.
- **Structure in comments/custom options:** descriptor sets can omit comments, index destinations must stay
  private, and custom options add imports for publishers.
- **Previous generated `.proto` as the sole history:** generated artifacts are otherwise safe to regenerate.
  The sidecar remains the durable contract input, with explicit migration required for missing old contracts.

## Expected behavior in `schema_evolution_spec.rb`

| Scenario | JSON | Protobuf |
|---|---|---|
| New field | Historical event has no new value | Same |
| Routing/rollover public rename | Both publishers reach the correct destination | Same; stable names/numbers map to current public names |
| Declared field deletion | Historical value is not indexed | Same; reserved number is dropped |
| Nested type rename | Both publishers index correct values | Same; message name and field numbers remain fixed |
| `JsonSafeLong` to `Int`, new index destination | Both write current destination; historical validation permits wider values | Both write current destination; retained `int64`, current `Int` range enforced |
| Public field rename, stable index name | Both write current index name | Same; retained protobuf name |
| Embedded type deletion | Historical data is not indexed | Same |
| Indexed type deletion | Historical events ignored | Same, envelope and raw |
| Incompatible type/shape change | Versioned publisher validation plus suitable index destination | Dump fails unless explicit proto name rotates the field |
| Rename declaration removed after successful dump | Historical JSON may still require declaration | Protobuf contract remains stable |
| Retired enum number | Historical enum contract applies | Known retired number becomes `nil` in the Ruby decoder under either syntax |

Each schema snapshot uses a separate publisher `DescriptorPool`, and historical payloads are encoded with
that snapshot's descriptor, not the latest descriptor. The indexer decodes with current artifacts only.
Test-only JSON schema versions may select the publisher fixture; they are never transmitted in protobuf.

## Verification plan

1. Rebase #1406 on latest `main`, reusing the existing dual-format harness rather than adding another one.
2. Implement durable contract reconciliation before rendering, schema-definition APIs, warnings, and runtime
   overrides; preserve #1388's wrapper/integration ownership and restack it afterward.
3. Replace blanket protobuf pending metadata with real publication/decoding. Cover actual indexed values,
   routing/rollover, nested rename history, rotations/restoration conflicts, deletion, enum handling, and
   mandatory narrowing range checks. Exercise proto2 and proto3 with independent publisher descriptors.
4. Run affected unit/acceptance/integration specs, signatures, artifact checks, focused sequential mutation
   tests, and `script/quick_build` before publishing.

## Resolved inconsistencies in the original proposal

- Historical JSON schemas merge current index metadata; they do not keep writing to old index destinations.
- Wire-parsable compatibility groups are not lossless conversion rules or arbitrary old/new-reader guarantees.
- Field numbers alone do not prove safe restoration; active public associations and retired incarnations need
  separate contracts, and legacy removed entries require explicit historical information.
- Enum renames need actual extension APIs rather than assuming the core enum DSL supports them.
- Known deleted envelope ownership must be established from validated original bytes, not a tag occurrence.
- Sampled-out validation cannot bypass the promised retained-wire range rejection.
- Proto2 consumers can differ from proto3 for retired values; test the actual Ruby decoder rather than assume
  textbook closed-enum behavior.
- Unknown fields in known messages can be discarded, so versionless decoding cannot reliably detect publishers
  ahead of the indexer.
