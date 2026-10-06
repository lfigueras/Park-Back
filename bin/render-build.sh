#!/usr/bin/env bash
# Build script run by Render on every deploy.
set -o errexit

bundle install
bundle exec rails assets:precompile   # also builds Tailwind via tailwindcss-rails
bundle exec rails assets:clean
bundle exec rails db:prepare           # creates DB and loads schema/migrations (primary + solid_* share one DB)
