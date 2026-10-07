# ParkBack

**Never lose your car (or motorcycle, bike, or truck) in a parking lot again.**

ParkBack is a mobile‑first web app that remembers where you parked and guides
you back. Save your GPS spot with a tap, add a few details and a photo, then let
ParkBack show you the distance, direction, and a map back to your vehicle.

<p align="center">
  <img src="docs/screenshots/save.png" alt="ParkBack – Save Parking Location screen" width="300">
  &nbsp;&nbsp;
  <img src="docs/screenshots/find.png" alt="ParkBack – Find My Car screen" width="300">
</p>

## Features

- **One‑tap save** – records your current GPS location.
- **Vehicle types** – car, motorcycle, bicycle, or truck (the map marker adapts).
- **Helpful details** – mall/building, floor, section/zone, slot number, landmark.
- **Photo of the spot** – take a new photo with the camera or upload one from your gallery, with a live preview.
- **Find My Car** – live walking distance, compass heading, an interactive map
  (Leaflet + OpenStreetMap) with a route line, and the time elapsed since you parked.
- **No sign‑up** – each browser owns its parking spot via a signed cookie.

## Tech stack

- **Ruby on Rails 8** (Ruby 3.3)
- **PostgreSQL** + **Active Storage** (photo uploads)
- **Hotwire** (Turbo + Stimulus) via import maps
- **Tailwind CSS v4**
- **Leaflet** / **OpenStreetMap** for mapping (no API key required)

## Getting started

### Prerequisites

- Ruby 3.3.x
- PostgreSQL running locally
- Node is **not** required (import maps + Tailwind are handled by Rails)

### Setup

```bash
git clone https://github.com/lfigueras/Park-Back.git
cd Park-Back
bin/setup            # installs gems, prepares the database
```

### Run

```bash
bin/dev              # starts Rails + Tailwind watcher
```

Then open http://localhost:3000.

> **Note:** browser geolocation requires `localhost` or HTTPS. The compass
> heading uses device orientation and only moves on a real phone (iOS asks for
> permission via the "Enable it" button).

## Production deployment

The production app is hosted on Render and uses Neon Postgres. Set
`RAILS_MASTER_KEY` from `config/master.key` and `DATABASE_URL` to the pooled
connection string for Neon’s `production` branch in the Render environment.
Keep the database URL secret. The pooled endpoint requires prepared statements
to be disabled, as configured in `config/database.yml`.

### Visitor analytics (Google Analytics 4)

1. At https://analytics.google.com, create a free standard GA4 property for
   ParkBack. Create a **Web** data stream with the public app URL and copy its
   **Measurement ID** (`G-...`), not the numeric property or stream ID.
2. In **Admin > Data streams > your web stream**, turn **Enhanced measurement**
   off. Also check **Configure tag settings > Show all > Manage automatic event
   detection** and turn off history-based page changes if enabled. ParkBack sends
   pageviews itself; automatic collection can duplicate visits and collect raw
   URLs or form interactions. Do not install another Google tag or GTM snippet.
3. Review consent requirements and update your privacy notice before enabling
   tracking. This integration does not include a consent banner or consent
   management. If prior consent is required, keep the measurement ID unset until
   consent-gated loading is implemented. GA4 uses first-party analytics cookies;
   Google Signals and ad personalization signals are disabled in this tag.
4. In Render, open **ParkBack > Environment**, set `GA4_MEASUREMENT_ID` to `G-...`,
   remove `PLAUSIBLE_SCRIPT_URL` if previously set, and save/redeploy with these
   code changes. No analytics subscription or separate hosting is required.
5. Visit the public app, then open **Reports > Realtime** at
   https://analytics.google.com. Use **Reports > Acquisition** for traffic sources
   and **Reports > Engagement > Pages and screens** for pageviews. Standard
   reports can take 24-48 hours to populate.

Tracking runs only in production with a valid measurement ID and counts full
page loads and Turbo visits. Query strings, URL fragments, and parking record
IDs are excluded from tracked page and referrer URLs. No GPS coordinates,
parking details, photos, or signed browser identifiers are added as event
properties. Keep automatic collection disabled to preserve these safeguards.

GA4 user counts estimate browsers/devices, not exact people. Its cookie-based
client ID is not a login or permanent person ID: clearing cookies or changing
devices can create another identity. No custom user ID is sent. Realtime shows
recent activity, not necessarily every open tab. Consent choices and blockers
can reduce counts, and traffic before installation is not recovered.

## Running tests

```bash
bin/rails test
```

## How it works

1. Open ParkBack and pick your vehicle type.
2. Tap **Save Parking Location** – your GPS spot is captured (add details/photo as needed).
3. When you're ready to leave, open the app and it jumps to **Find My Car**.
4. Follow the distance, compass arrow, and map back to your vehicle.
5. Tap **I found my …** to clear the spot.
