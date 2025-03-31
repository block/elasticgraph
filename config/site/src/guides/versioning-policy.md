---
layout: markdown
title: Versioning Policy
permalink: /guides/versioning-policy/
nav_title: Versioning Policy
menu_order: 3
---

ElasticGraph does _not_ strictly follow the [SemVer](https://semver.org/) spec. We followed that early in the project's life
cycle and realized that it obscures some important compatibility information.

ElasticGraph's versioning policy is designed to communicate compatibility information related to the following stakeholders:

* **Application maintainers**: engineers that define an ElasticGraph schema, maintain project configuration, and perform upgrades.
* **Data publishers**: systems that publish data into an ElasticGraph application for ingestion by an ElasticGraph indexer.
* **GraphQL clients**: clients of the GraphQL API of an ElasticGraph application.

We use the following versioning scheme:

* Version numbers are in a `MAJOR.MINOR.PATCH` format.
* Increments to the PATCH version indicate that the new release contains no backwards incompatibilities for any stakeholders.
  It may contain bug fixes, new features, internal refactorings, and dependency upgrades, among other things. You can expect that
  PATCH level upgrades are always safe--just update the version in your bundle, generate new schema artifacts, and you should be done.
* Increments to the MINOR version indicate that the new release contains some backwards incompatibilities that may impact the
  **application maintainers** of some ElasticGraph applications. MINOR releases may include renames to configuration settings,
  changes to the schema definition API, and new schema definition requirements, among other things. You can expect that MINOR
  level upgrades can usually be done in 30 minutes or less (usually in a single commit!), with release notes and clear errors
  from ElasticGraph command line tasks providing guidance on how to upgrade.
* Increments to the MAJOR version indicate that the new release contains some backwards incompatibilities that may impact the
  **data publishers** or **GraphQL clients** of some ElasticGraph applications. MAJOR releases may include changes to the GraphQL
  schema that require careful migration of **GraphQL clients** or changes to how indexing is done that require a dataset to be
  re-indexed from scratch (e.g. by having **data publishers** republish their data into an ElasticGraph indexer running the new
  version). You can expect that the release notes will include detailed instructions on how to perform a MAJOR version upgrade.

Deprecation warnings may be included at any of these levels--for example, a PATCH release may contain a deprecation warning
for a breaking change that may impact **application maintainers** in an upcoming MINOR release, and a MINOR release may
contain deprecation warnings for breaking changes that may impact **data publishers** or **GraphQL clients** in an upcoming
MAJOR release.

Each version level is cumulative over the prior levels. That is, a MINOR release may include PATCH-level changes in addition
to backwards incompatibilities that may impact **application maintainers**. A MAJOR release may include PATCH-level or
MINOR-level changes in addition to backwards incompatibilities that may impact **data publishers** or **GraphQL clients**.

Note that _all_ gems in this repository share the same version number. Every time we cut a release, we increment the version
for _all_ gems and release _all_ gems, even if a gem has had no changes since the last release. This is simpler to work with
than the alternatives.

{: .alert-note}
**Note**{: .alert-title}
We'll be releasing 1.0.0 soon! Before then, this same versioning policy applies, but our version numbers use a `0.MAJOR.MINOR.PATCH` format.
