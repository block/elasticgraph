# Contribution Guide

There are many ways to be an open source contributor, and we're here to help you on your way! You may:

* Propose ideas in our [discord](https://discord.gg/8m9FqJ7a7F)
* Raise an issue or feature request in our [issue tracker](https://github.com/block/elasticgraph/issues)
* Help another contributor with one of their questions, or a code review
* Suggest improvements to our Getting Started documentation by supplying a Pull Request
* Evangelize our work together in conferences, podcasts, and social media spaces

This guide is for you.

## Development Prerequisites

| Requirement    | Tested Version | Installation Instructions                                                 |
|----------------|----------------|---------------------------------------------------------------------------|
| Ruby           | 3.4.x          | [ruby-lang.org](https://www.ruby-lang.org/en/documentation/installation/) |
| Docker Engine  | 27.x           | [docker.com](https://docs.docker.com/engine/install/)                     |
| Docker Compose | 2.29.x         | [docker.com](https://docs.docker.com/compose/install/)                    |

### Ruby

This project is written in Ruby, a dynamic, open source programming language with a focus on simplicity and productivity.

You may verify your `ruby` installation via the terminal:

```bash
$ ruby -v
ruby 3.4.2 (2025-02-15 revision d2930f8e7a) +PRISM [arm64-darwin24]
```

If you do not have Ruby, we recommend installing it using one of the following:

* [RVM](https://rvm.io/)
* [asdf](https://asdf-vm.com/)
* [rbenv](https://rbenv.org/)
* [ruby-install](https://github.com/postmodern/ruby-install)

### Ruby Dependencies

Ruby dependencies are managed using [bundler](https://bundler.io/), which comes installed with Ruby.
To install Ruby dependencies, run:

```bash
$ bundle install
```

Once that is done, prefix Ruby commands (`ruby`, `rspec`, `rake`, etc) with `bundle exec` in order to run them in the context of the project bundle.

### Docker and Docker Compose

This project uses Docker Engine and Docker Compose to run Elasticsearch and OpenSearch locally. We recommend installing
[Docker Desktop](https://docs.docker.com/desktop/) to get both Docker dependencies.

## Customizing the Development Environment

The project bundle only contains the gems necessary for what runs on CI.
For local development, you may want to use some additional gems, such as:

* [debug](https://github.com/ruby/debug) for debugging
* [vernier](https://github.com/jhawthorn/vernier) for profiling
* [solargraph](https://solargraph.org/) for an LSP implementation used by an IDE

Different engineers have different preferences around what gems to include, so the standard project bundle
does not include gems like these. However, support is included to customize the development environment:

* Make a `Gemfile-custom` file listing the additional gems you want to include.
  See [Gemfile-custom.example](Gemfile-custom.example) for an example.
* Run `source script/enable_custom_gemfile`.

This will set the `BUNDLE_GEMFILE` and `BUNDLE_LOCKFILE` environment variables in your shell session
so that `bundle exec` will run in the context of your custom bundle.

## Codebase Overview

To understand how the different parts of the codebase fit together, see the [codebase overview](CODEBASE_OVERVIEW.md).

## Using AI Tools

Using AI tools such as [Goose](https://block.github.io/goose/), [ChatGPT](https://chatgpt.com/), [Cursor](https://cursor.com/),
or [Claude](https://claude.ai/) to contribute is encouraged. However:

* AI tools are assistants and should not replace critical thinking and judgement.
* We expect contributors to understand every line of code submitted in a PR--in the long run, humans are on the hook for maintaining it!

If you use an AI agent, feel free to leverage the growing [AI memory bank](https://github.com/block/elasticgraph/tree/main/ai-memory),
and if updates made by your AI agent to that directory seem worth keeping, please include them in your submitted PR!

We also maintain a [hints file for Goose](https://github.com/block/elasticgraph/blob/main/.goosehints) which you can adapt for use by
other AI agents.

## Build Scripts and Executables

The codebase includes a variety of build scripts and executables which are useful for local development:

* `script/quick_build`: Performs an abridged version of the CI build. This is generally the most complete CI build we run locally.
  **We recommend running it before opening a PR.**
* `script/type_check`: Runs a [steep](https://github.com/soutaro/steep) type check.
* `script/spellcheck`: Spellchecks the codebase using [codespell](https://github.com/codespell-project/codespell).
* `script/run_specs`: Runs the test suite.
* `script/run_gem_specs [gem_name]`: Runs the test suite for one ElasticGraph gem.

### Running Tests

We use [RSpec](https://rspec.info/) as our test framework.

Each of the ElasticGraph gems has its own test suite in `spec` (e.g. `elasticgraph-support/spec` contains the tests for
`elasticgraph-support`).

Run the entire suite:

```bash
script/run_specs
```

To test a single gem (e.g., `elasticgraph-support`):

```bash
# From the root:
bundle exec rspec elasticgraph-support/spec

# Alternatively run a gem's specs within the context of that gem's bundle, with code coverage tracked:
script/run_gem_specs elasticgraph-support

# Alternatively, you can run tests within a subdirectory:
cd elasticgraph-support
bundle exec rspec
```

The RSpec CLI is extremely flexible. Here are some useful options:

```bash
# See RSpec CLI options
bundle exec rspec --help

# Run all specs in one directory
bundle exec rspec path/to/dir

# Run all specs in one file
bundle exec rspec path/to/dir/file_spec.rb

# Run the spec defined at a specific line in a file
bundle exec rspec path/to/dir/file_spec.rb:47

# Run only the tests that failed the last time they ran
bundle exec rspec --only-failures

# Run just failures, and halt after the first failure (designed to be run repeatedly)
bundle exec rspec --next-failure
```

In addition, you can run tests in parallel by using `script/flatware_rspec` instead of `bundle exec rspec`:

```bash
script/flatware_rspec path/to/dir
```

Running tests in parallel using flatware tends to be faster for large test suite runs, but is usually slower for running a
small subset of the test suite (e.g. one file or directory).

`script/quick_build`, `script/run_specs`, and `script/run_gem_specs` use flatware when appropriate. (It's not always faster!)

The integration and acceptance tests require Elasticsearch or OpenSearch to be running locally on a specific
port; to boot it for those tests, run one of the following in a separate terminal and leave it running:

```bash
bundle exec rake elasticsearch:test:boot
# or
bundle exec rake opensearch:test:boot
```

Note: our integration and acceptance tests hammer Elasticsearch/OpenSearch pretty hard, particularly when running
tests in parallel. Sometimes that puts the datastore into a bad state. When this happens, simply kill the `rake *:test:boot`
process, and run it again; then re-run the tests.

## Project Website

The source code for https://block.github.io/elasticgraph/ lives in [config/site](config/site).

To build it locally, run:

```bash
bundle exec rake site:build
```

To serve it locally, run:

```bash
bundle exec rake site:serve
```

Then visit http://localhost:4000/elasticgraph/ in your browser. Local edits to the site will be reflected when you reload a page.

### API Documentation

ElasticGraph's Ruby code is documented using [YARD](https://yardoc.org/). You can view the rendered API docs in the context of the
project website using the same `site:serve` rake task (just visit http://localhost:4000/elasticgraph/api-docs/main/). However, that task
fully regenerates the documentation from scratch and it's not very quick. If you're working on multiple changes to the API documentation,
you'll get a faster feedback loop using the `site:preview_docs:[gem name]` tasks. For example, to preview the docs of
[elasticgraph-schema_definition](elasticgraph-schema_definition), run:

```bash
bundle exec rake site:preview_docs:elasticgraph-schema_definition
```

Then visit http://localhost:8808/. The preview task will rebuild the parts of the generated docs impacted by your edits, and is quite fast.

## Maintenance Tasks

Common codebase maintenance tasks are documented in the [maintainer's runbook](MAINTAINERS_RUNBOOK.md).

---

## Communications

### Issues

Anyone from the community is welcome (and encouraged!) to raise issues via
[GitHub Issues](https://github.com/block/elasticgraph/issues).

### Discussions

Design discussions and proposals take place on [GitHub discussions](https://github.com/block/elasticgraph/discussions).
We advocate an asynchronous, written discussion model - so write up your thoughts and invite the community to join in!

In addition, we have a [discord channel](https://discord.gg/8m9FqJ7a7F) for synchronous communication. Discord is best
for questions and general conversation.

### Continuous Integration

Build and test cycles are run on every commit to every branch on [GitHub Actions](https://github.com/block/elasticgraph/actions).

## Contribution

We review contributions to the codebase via GitHub's Pull Request mechanism. We have
the following guidelines to ease your experience and help our leads respond quickly
to your valuable work:

* Start by proposing a change either on Discord (most appropriate for small
  change requests or bug fixes) or in Discussions (most appropriate for design
  and architecture considerations, proposing a new feature, or where you'd
  like insight and feedback).
* Cultivate consensus around your ideas; the project leads will help you
  pre-flight how beneficial the proposal might be to the project. Developing early
  buy-in will help others understand what you're looking to do, and give you a
  greater chance of your contributions making it into the codebase! No one wants to
  see work done in an area that's unlikely to be incorporated into the codebase.
* Fork the repo into your own namespace/remote.
* Work in a dedicated feature branch. Atlassian wrote a great
  [description of this workflow](https://www.atlassian.com/git/tutorials/comparing-workflows/feature-branch-workflow).
* When you're ready to submit a pull request:
    * Squash your commits into a single one (or an appropriate small number of commits), and
      rebase atop the upstream `main` branch. This will limit the potential for merge
      conflicts during review, and helps keep the audit trail clean. A good writeup for
      how this is done is
      [here](https://medium.com/@slamflipstrom/a-beginners-guide-to-squashing-commits-with-git-rebase-8185cf6e62ec), and if you're
      having trouble - feel free to ask a member or the community for help or leave the commits as-is, and flag that you'd like
      rebasing assistance in your PR! We're here to support you.
    * Please run `script/quick_build` and fix any failures (it'll be faster to get your change merged if it already passes the build!)
      * If you're not sure how to fix the failures (and an AI agent isn't helping), feel free to submit what you have and we'll
        recommend the fix.
    * Open a PR in the project to bring in the code from your feature branch.
    * The maintainers noted in the [CODEOWNERS file](https://github.com/block/elasticgraph/blob/main/.github/CODEOWNERS)
      will review your PR and optionally open a discussion about its contents before moving forward.
    * Remain responsive to follow-up questions, be open to making requested changes, and...
      You're a contributor!
* Remember to respect everyone in our development community. Guidelines
  are established in our [Code of Conduct](https://github.com/block/elasticgraph/blob/main/CODE_OF_CONDUCT.md).
