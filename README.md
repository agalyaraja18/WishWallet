<h1 align="center">WishWallet</h1>
<p align="center"><strong>Wish it. Want it. Win it.</strong></p>
<p align="center">Save shopping links, fetch product details, and organize the things you want to buy later.</p>

## Features

- Save product links manually while offline, or fetch product names, prices, and images when connected to the WishWallet API.
- Organize wishes into custom categories.
- Add and remove wishes and categories.
- Keep account and wishlist data saved locally or through the API.
- Use a one-time recovery code to reset a forgotten password.

## Download APK

Download the latest Android APK from [GitHub Releases](https://github.com/agalyaraja18/WishWallet/releases/latest). After setting the `WISHWALLET_API_BASE_URL` repository variable, pushing a version tag automatically builds an API-enabled APK and attaches it to the release.

An APK built without an API URL works in local/offline mode: enter wish names and links manually, but automatic product lookup is unavailable.

### Deploy a free test API on Render

1. Sign in to [Render](https://dashboard.render.com/) and create a Blueprint from this GitHub repository. Render reads [`render.yaml`](./render.yaml) and creates the API and PostgreSQL database.
2. Wait for the `wishwallet-api` service to finish deploying, then copy its HTTPS URL from the Render dashboard.
3. In the GitHub repository, open **Settings → Secrets and variables → Actions → Variables**, create `WISHWALLET_API_BASE_URL`, and set it to the service URL without a trailing slash.
4. Push a new version tag (for example, `v1.0.1`). The release workflow builds an APK with that API URL and attaches it to the GitHub release.

This free setup is for testing only: Render's free API service can sleep between requests, and its free PostgreSQL database expires after 30 days, which deletes its data. The app allows up to 90 seconds for a lookup so the API has time to wake up. For a local APK build after deploying, run:

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example.com
```

Use the Render URL in place of `https://your-api.example.com`, without a trailing slash. The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`.

## Project Structure

```text
WishWallet/
├── android/                 # Android project
├── assets/                  # App and brand images
├── backend/
│   ├── app/main.py          # FastAPI backend
│   └── requirements.txt     # Python dependencies
├── ios/                     # iOS project
├── lib/main.dart            # Flutter app
├── test/widget_test.dart    # Widget tests
├── web/                     # Web app files
├── pubspec.yaml             # Flutter dependencies and configuration
└── README.md
```

## Tech Stack

| Technology | Purpose |
| --- | --- |
| Flutter and Dart | Android, iOS, and web app |
| Python and FastAPI | Backend API |
| SQLAlchemy | Database access |
| MySQL | Persistent database; SQLite is the local development default |
| Shared Preferences | Offline account and wishlist storage |
| Cloudinary | Optional image storage |