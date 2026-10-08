# ParkBack

A mobile-first app to save your parking location and find your way back using
GPS, distance, a compass, and a map. Supports cars, motorcycles, bicycles, and
trucks. No account required.

**[Open ParkBack](https://parkback-2zwf.onrender.com/)**

## Features

- Save GPS with details and an optional photo (up to 5 MB); without GPS, a photo is required.
- View your saved spot, distance, direction, and OpenStreetMap map.
- Clear your saved spot when you find your vehicle.
- Private, browser-owned records with a seven-day expiry.

## Local Setup

Requires Ruby 3.3 and PostgreSQL. Built with Rails 8, Hotwire, and Tailwind CSS 4;
Node is not required.

```sh
git clone https://github.com/lfigueras/Park-Back.git
cd Park-Back
bin/setup
bin/dev
```

Open http://localhost:3000. GPS requires localhost or HTTPS; compass support
depends on your device and permissions.

## Production

Hosted on Render with Neon Postgres and private, S3-compatible Neon Object
Storage. Set these environment variables in Render:

- `RAILS_MASTER_KEY`
- `DATABASE_URL`: pooled Neon Postgres connection string.
- `NEON_STORAGE_ENDPOINT`: production branch's S3 endpoint.
- `NEON_STORAGE_ACCESS_KEY_ID`: storage credential's `token_id`.
- `NEON_STORAGE_SECRET_ACCESS_KEY`: credential's `s3_secret_access_key`.

Storage defaults: region `ap-southeast-1`, bucket `parkback-photos`. Override with
`NEON_STORAGE_REGION` and `NEON_STORAGE_BUCKET` if needed. Production uploads
stay disabled without complete storage settings; development uses local disk.
Keep the bucket private and never commit credentials. Switching storage cannot
recover photos already lost from temporary disk.

Optional analytics: set `GA4_MEASUREMENT_ID` and disable GA4's automatic/enhanced
measurement because the app sends pageviews itself. Analytics requires opt-in;
counts estimate browsers/devices, not exact people.

Daily aggregate views are separate from GA4: only UTC date, `save`/`find` category
and count are stored. Reports cover 90 days; new views trigger older-total cleanup.
Run `bin/rails traffic:report` against the
intended database or view `daily_page_views` in Neon's SQL Editor. Refreshes count
again; basic bot filtering is not exhaustive. This does not count unique users.

For time-of-day totals, run `bin/rails traffic:hourly` (UTC and Philippine time)
or query `hourly_page_views`. Its `hour_start` is rounded to the UTC hour, not an
individual visit timestamp. Existing daily counts have no recoverable time data.

## Privacy

Maps are on by default and can be disabled; GPS requires the location button.
Photos are available only through owner-checked app routes. Expired records are
removed on subsequent requests. Deletion removes app access, but Neon may retain
copies in provider history or backups. Original photos may contain EXIF metadata.
See [Privacy & choices](https://parkback-2zwf.onrender.com/privacy) for details.

## Checks

```sh
bin/rails test
bin/rubocop
bin/bundler-audit
bin/importmap audit
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
```
