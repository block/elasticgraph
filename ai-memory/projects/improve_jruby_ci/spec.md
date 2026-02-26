## Context

We recently added JRuby to the CI build matrix in #999. It's working well but there are a few loose ends to tie up.

## DONE: Remove `:except_jruby` from `elasticgraph-local` specs

To get the JRuby CI build to pass, we tagged a couple of `elasticgraph-local` specs with `:except_jruby`. These
specs pass `--daemonize` when booting ElasticGraph locally, and `--daemonize` doesn't work on JRuby because the
rack implementation of it uses `fork`. However, the daemonization is only a test thing to allow the test to boot
the server and then query it. The underlying logic doesn't depend on daemonization and should work just fine on
JRuby. We would like to close this gap and properly cover it.

A prior attempt at fixing this was done in #1037. However, I'm not satisfied with the solution: it hacks the
implementation to treat `--daemonize` in a special way to avoid using `fork`. I don't want to complicate the
implementation just for JRuby. Instead, I'd like to find a way to isolate the JRuby work around to only being
in the tests. The implementation should stay simple and not branch on the basis of a `--daemonize` flag. However,
if we need to introduce a seam that the tests can hook into for JRuby, that's fine.

## TODO: Improve JRuby CI wall clock time

The JRuby build part is very slow--it takes 50+ minutes whereas the longest other build part takes about 20 minutes.
We want to optimize things by running multiple JRuby build parts in parallel so that JRuby is no longer the slowest
build part--that way, testing on JRuby doesn't add to how long engineers have to wait for CI build status.

Figure out an optimal way to split up the test suite.

I'm also not terribly happy with the 18-20m build time of some of the other build parts. While the focus here should
be on solving the slow JRuby wall clock build time, if there's a general purpose solution that applies to the builds
on other Ruby interpreters, great! But if it needs a different solution for JRuby vs others, let's just focus on
JRuby here.
