# WishWallet

WishWallet is a Flutter wishlist app using the supplied blush-and-red visual design. Fetch product prices and images from shopping links, organize wishes into categories, and manage them from the wishlist and profile screens.

## Run the mobile app

1. Install Flutter and an Android/iOS device or emulator.
2. From the project root, run `flutter pub get`.
3. Run `flutter run`.

The app works offline: accounts and their wishlists are stored separately on the device/browser. New accounts start without categories. A new account receives a one-time recovery code; save it when it is shown, because it is needed for Forgot Password and is replaced after each successful reset. Create a local account from **Create it**, or choose **Continue with demo account** on the login screen to open the persistent sample wishlist. Offline mode supports viewing and organizing saved demo data; adding products requires the API to fetch a price.

Automatic product price lookup requires the Python API; browser-only/offline demo mode cannot read shopping sites directly. To use price lookup in Chrome, open two terminals:

1. In the first terminal:
   ```powershell
   cd C:\Projects\WishWallet\backend
   python -m pip install -r requirements.txt
   python -m uvicorn app.main:app --reload
   ```
   Without a `backend/.env`, the API uses a local SQLite database.
2. In the second terminal:
   ```powershell
   cd C:\Projects\WishWallet
   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
   ```
3. Create an account in the app, open **Add a new wish**, paste a direct product-page link, then choose **Fetch name and price from link**. Save is enabled once a price has been found. The product card shows that fetched price.

Some stores block automated requests or don't publish product price metadata. Those links can't be saved with a price until the store makes it available; price entry is intentionally not offered.

## Run the Python API

1. Create a MySQL database named `wishwallet`.
2. Copy `backend/.env.example` to `backend/.env` and set `DATABASE_URL`, a unique `JWT_SECRET`, and Cloudinary credentials.
3. Install dependencies with `python -m pip install -r backend/requirements.txt`.
4. Start the API from the `backend` directory with `python -m uvicorn app.main:app --reload`.

For development without MySQL, the API defaults to a SQLite file. Set `DATABASE_URL` to the MySQL URL in `.env.example` to use MySQL.

Connect the app to the API with `flutter run --dart-define=API_BASE_URL=http://<device-reachable-host>:8000`. For the Android emulator, the host is commonly `10.0.2.2`. Android debug/profile builds allow HTTP for local development; use HTTPS for iOS and production builds. With the API configured, the app uses it for registration, login, password changes, account deletion, product metadata scanning, and category/wish CRUD. Forgot Password uses the account ID and its one-time recovery code; after a successful reset, save the replacement code shown. Recovery-code hashes are stored by the API, not the plain-text codes.

The API docs are available at `/docs`. Product pages may omit metadata or block automated requests, so check scanned details before saving. Cloudinary image storage is used when all three Cloudinary settings are provided; otherwise images keep their original public URL.
