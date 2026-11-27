<h1 align="center">WishWallet</h1>
<p align="center"><strong>Wish it. Want it. Win it.</strong></p>
<p align="center">Save shopping links, fetch product details, and organize the things you want to buy later.</p>

## Features

- Save product links and fetch product names, prices, and images when the store provides them.
- Organize wishes into custom categories.
- Add and remove wishes and categories.
- Keep account and wishlist data saved locally or through the API.
- Use a one-time recovery code to reset a forgotten password.

## Download APK

See [GitHub Releases](https://github.com/agalyaraja18/WishWallet/releases) for downloadable APKs. No APK release has been published yet.

To build an APK locally, run `flutter build apk --release`. The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`.

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