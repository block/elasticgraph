# Contribution Guide

There are many ways to be an open source contributor, and we're here to help you on your way! You may:

* Propose ideas in our [discord](https://discord.gg/8m9FqJ7a7F)
* Raise an issue or feature request in our [issue tracker](https://github.com/block/elasticgraph/issues)
* Help another contributor with one of their questions, or a code review
* Suggest improvements to our Getting Started documentation by supplying a Pull Request
* Evangelize our work together in conferences, podcasts, and social media spaces.

This guide is for you.

## Development Prerequisites

| Requirement    | Tested Version | Installation Instructions                                                 |
|----------------|----------------|---------------------------------------------------------------------------|
| Ruby           | 3.2.x, 3.3.x   | [ruby-lang.org](https://www.ruby-lang.org/en/documentation/installation/) |
| Docker Engine  | 27.x           | [docker.com](https://docs.docker.com/engine/install/)                     |
| Docker Compose | 2.29.x         | [docker.com](https://docs.docker.com/compose/install/)                    |

### Ruby

This project is written in Ruby, a dynamic, open source programming language with a focus on simplicity and productivity.

You may verify your `ruby` installation via the terminal:

```
$ ruby -v
ruby 3.3.4 (2024-07-09 revision be1089c8ec) [arm64-darwin23]
```

If you do not have Ruby, we recommend installing it using one of the following:

* [RVM](https://rvm.io/)
* [asdf](https://asdf-vm.com/)
* [rbenv](https://rbenv.org/)
* [ruby-install](https://github.com/postmodern/ruby-install)

Once you have Ruby installed, install the development dependencies by running `bundle install`.

### Docker and Docker Compose

This project uses Docker Engine and Docker Compose to run Elasticsearch and OpenSearch locally. We recommend installing
[Docker Desktop](https://docs.docker.com/desktop/) to get both Docker dependencies.

---

## Communications

### Issues

Anyone from the community is welcome (and encouraged!) to raise issues via
[GitHub Issues](https://github.com/block/elasticgraph/issues).

### Discussions

Design discussions and proposals take place in our [discord](https://discord.gg/8m9FqJ7a7F).

We advocate an asynchronous, written debate model - so write up your thoughts and invite the community to join in!

### Continuous Integration

Build and Test cycles are run on every commit to every branch on [GitHub Actions](https://github.com/block/elasticgraph/actions).

## Contribution

We review contributions to the codebase via GitHub's Pull Request mechanism. We have
the following guidelines to ease your experience and help our leads respond quickly
to your valuable work:

* Start by proposing a change either in Issues (most appropriate for small
  change requests or bug fixes) or in Discussions (most appropriate for design
  and architecture considerations, proposing a new feature, or where you'd
  like insight and feedback)
* Cultivate consensus around your ideas; the project leads will help you
  pre-flight how beneficial the proposal might be to the project. Developing early
  buy-in will help others understand what you're looking to do, and give you a
  greater chance of your contributions making it into the codebase! No one wants to
  see work done in an area that's unlikely to be incorporated into the codebase.
* Fork the repo into your own namespace/remote
* Work in a dedicated feature branch. Atlassian wrote a great
  [description of this workflow](https://www.atlassian.com/git/tutorials/comparing-workflows/feature-branch-workflow)
* When you're ready to offer your work to the project, first:
* Squash your commits into a single one (or an appropriate small number of commits), and
  rebase atop the upstream `main` branch. This will limit the potential for merge
  conflicts during review, and helps keep the audit trail clean. A good writeup for
  how this is done is
  [here](https://medium.com/@slamflipstrom/a-beginners-guide-to-squashing-commits-with-git-rebase-8185cf6e62ec), and if you're
  having trouble - feel free to ask a member or the community for help or leave the commits as-is, and flag that you'd like
  rebasing assistance in your PR! We're here to support you.
* Open a PR in the project to bring in the code from your feature branch.
* The maintainers noted in the [CODEOWNERS file](https://github.com/block/elasticgraph/blob/main/.github/CODEOWNERS)
  will review your PR and optionally open a discussion about its contents before moving forward.
* Remain responsive to follow-up questions, be open to making requested changes, and...
  You're a contributor!
* And remember to respect everyone in our global development community. Guidelines
  are established in our [Code of Conduct](https://github.com/block/elasticgraph/blob/main/CODE_OF_CONDUCT.md).
