# ParkBack Firebase Setup

The React application lives in `frontend/` and is published to GitHub Pages by `.github/workflows/deploy-pages.yml`. Rails and Neon remain unchanged as the production app and rollback path until the Firebase version is verified. Existing Rails records and photos are not imported.

## Firebase Project

1. Create a Firebase project and register a Web app.
2. Enable **Authentication > Sign-in method > Anonymous**.
3. Create the default Firestore database in **Standard / Production** mode in `asia-southeast1` (Singapore). The Spark plan currently includes 1 GiB of stored documents, 50,000 reads/day, 20,000 writes/day, 20,000 deletes/day, and 10 GiB/month outbound transfer for the first database.
4. Create a Realtime Database in Singapore. Realtime Database Spark currently includes 1 GB stored and 10 GB/month downloaded. Photos are Base64-encoded, so a 5 MB image uses about 6.7 MB of this quota. Review the current Firebase pricing page before launch because quotas and eligibility can change.
5. Copy the Web app settings from Project settings into `frontend/.env.local`, using `frontend/env.example` as the template. Set `VITE_FIREBASE_DATABASE_URL` to the exact URL shown for the Realtime Database. These client settings are not service-account secrets; never put an Admin SDK key in the frontend.
6. Add `lfigueras.github.io` to Authentication's authorized domains. Enable App Check only after configuring its provider in the client; it is not enforced by this app yet.

This Spark architecture does not use Firebase Storage, Firebase Hosting, Cloud Functions, or Firestore TTL. It does not require linking a billing account for those features because they are intentionally omitted. Firebase and GitHub can still apply their quotas and terms.

## Local Development

Use Java 21 or newer with the current Firebase CLI for the Auth, Firestore, and Realtime Database emulators. From the repository root:

```sh
npm --prefix frontend install
npx firebase-tools emulators:start --only auth,firestore,database --project demo-parkback
```

In another terminal, set the dummy demo Firebase values in `frontend/.env.local`, including `VITE_FIREBASE_DATABASE_URL=https://demo-parkback-default-rtdb.firebaseio.com`, set `VITE_USE_FIREBASE_EMULATORS=true`, and run:

```sh
npm --prefix frontend run dev
```

Use only the `demo-parkback` project ID with emulators. Do not put a real Firebase project ID in the emulator command.

To run rules tests with the emulators active:

```sh
npm --prefix frontend run test:rules
```

After anonymous sign-in, the app purges that user's expired Firestore records and RTDB photo nodes before rendering a route. This is opportunistic cleanup, not a scheduled job: expired data can remain stored if the user never returns. Firestore rules stop direct reads of expired spots after seven days.

## Deploy

Deploy Firestore and Realtime Database rules after reviewing them. From the repository root, run:

```sh
npx firebase-tools deploy --project parkback-ljf22 --only firestore:rules,firestore:indexes,database
```

For GitHub Pages, set the repository's **Settings → Pages → Build and deployment → Source** to **GitHub Actions**. Add these repository Actions variables under **Settings → Secrets and variables → Actions → Variables**: `VITE_FIREBASE_API_KEY`, `VITE_FIREBASE_AUTH_DOMAIN`, `VITE_FIREBASE_PROJECT_ID`, `VITE_FIREBASE_DATABASE_URL`, `VITE_FIREBASE_APP_ID`, and optionally `VITE_FIREBASE_MEASUREMENT_ID`. The workflow publishes the Vite build at `https://lfigueras.github.io/Park-Back/` on pushes to `main`; `404.html` provides SPA route fallback. Firebase client config is public, but never add service-account credentials to Actions variables or the repo.

## Existing Rails Data

This does not automatically transfer records from Rails/Postgres. Existing locations are linked to a private Rails browser cookie, while the new app uses a Firebase anonymous identity. Keep the Rails deployment and its database intact until a one-time, cookie-authorized migration or an explicit user export/import process is designed and verified. Do not point the live domain at GitHub Pages until that decision is made and the privacy notice is updated to the final data location and visit-triggered cleanup behavior.
