# Site Config README

The documentation site is built on the `gh-pages` branch using the GitHub action `publish-site.yml`.

To build the site and documentation locally, run `bundle exec rake -T | grep site` to view a list of commands. These commands are sourced from the Rake tasks in `config/site/Rakefile`.

## CSS Styling

CSS Styling is powered by [Tailwind CSS](https://tailwindcss.com/) via the `package.json` script: `npm run build:css`.

Tip: most LLM's do a good job of generating Tailwind CSS classes.

Extract common classes to `src/_config.yaml`

We're using the `@tailwindcss/typography` plugin to style the markdown content automatically. See https://github.com/tailwindlabs/tailwindcss-typography for more information.

If a new class is used in an HTML file, you'll need to restart the site serve rake task to ensure the new class is included in `main.css` by Tailwind.

## Markdown

Write any standalone content (non-documentation) as regular Markdown files with front matter. (see `src/about.md` for example).

## Icons

Icons are SVG's copied from [heroicons](https://heroicons.com/) (MIT licensed).

Include them via `{% include svg/document-duplicate.svg %}`
