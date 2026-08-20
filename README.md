# Professional Mobiles & Laptop Service - Business Manager

Offline-first Android app (Flutter) for a mobile/laptop repair shop that also
buys and sells 2nd hand phones: customers, service job cards, spare parts &
accessories inventory, sales billing, 2nd hand mobile purchase/sale,
suppliers & purchases, expenses, a full Profit & Loss engine, A5 bill
printing with your logo, staff PIN + permissions, and local/Google Drive
backup. No server, no internet required for daily use.

---

## 1. Why you're building this yourself

This project was written in a sandboxed environment that cannot reach
Google's Flutter/Dart package servers, so it could not be compiled into a
ready `.apk` there. Everything else is done: **~10,000 lines** of real,
organized Dart source across ~65 files, a complete offline SQLite schema,
and every screen described in the spec. Turning it into an installable app
takes about 10 minutes with the steps below.

## 2. What you need

- A computer (Windows/Mac/Linux) with the **Flutter SDK** installed. If you
  don't have it: https://docs.flutter.dev/get-started/install (also
  installs the Android SDK/toolchain via `flutter doctor`).
- No Android Studio required, though it makes step 3 easier if you have it.

If you'd rather not install anything locally, upload this folder to
**Codemagic** (codemagic.io, free tier) or a GitHub repo + a simple
GitHub Actions workflow - both can run `flutter build apk` for you in the
cloud and hand you back the `.apk`.

## 3. Build steps

```bash
# 1. Unzip this project, then from inside the project folder:
cd professional_mobiles

# 2. Generate the Android platform folder (safe - only adds android/,
#    never touches the lib/ source that's already here):
flutter create --platforms=android .

# 3. Add these two permissions to android/app/src/main/AndroidManifest.xml,
#    inside the <manifest> tag (above <application>):
#    <uses-permission android:name="android.permission.CAMERA"/>
#    <uses-permission android:name="android.permission.INTERNET"/>
#    (CAMERA is for service/2nd-hand phone photos; INTERNET is only used
#    for the optional Google Drive backup - the rest of the app is 100%
#    offline.) Only needed if you're building locally - the GitHub Actions
#    workflow (.github/workflows/build-apk.yml) already does this step
#    for you automatically, every build.

# 4. Fetch packages:
flutter pub get

# 5. Generate the app icon from your logo:
dart run flutter_launcher_icons

# 6. Build the installable APK:
flutter build apk --release

# Your APK is now at:
# build/app/outputs/flutter-apk/app-release.apk
# Copy it to the phone and install (enable "Install unknown apps" once).
```

To test on a connected phone/emulator without building an APK first, use
`flutter run` instead of step 6.

## 4. First launch

The very first time the app opens it asks you to create the **Admin
account** (name + PIN). That PIN gates all profit/cost figures everywhere
in the app (spec section 28) - customer-facing bills never show purchase
cost, spare part cost, or profit regardless of who's logged in. Add staff
accounts and pick exactly what each one can see under **Settings → Staff &
Permissions**.

## 5. Google Drive backup setup (optional - skip if you don't need it)

Everything works fully offline without this. If you want automatic Drive
backups too:

### If you build APKs via the GitHub Actions workflow (recommended)

Every APK built by CI used to be signed with a **brand new, throwaway
debug keystore generated fresh on each run** - so its SHA-1 fingerprint
was different every single build, which silently broke Google sign-in
(`DEVELOPER_ERROR` / "no response after picking an account") the moment
you built again after registering an OAuth client. The workflow now
restores a **stable** keystore from a repository secret instead, so the
SHA-1 never changes once you've set this up:

1. In this repo: **Settings → Secrets and variables → Actions → New
   repository secret**, name it `DEBUG_KEYSTORE_BASE64`, and paste in the
   base64-encoded keystore your assistant generated for you (delivered as
   a file alongside these instructions - keep the original `.jks` file
   itself somewhere safe too, e.g. a password manager; losing it just
   means a future rebuild gets a new SHA-1 and you re-register the OAuth
   client, it does **not** lock you out of your own data).
2. Go to https://console.cloud.google.com → create a project → enable the
   **Google Drive API**.
3. Create an **OAuth 2.0 Client ID** of type "Android" using:
   - Package name: `com.example.pro_app` (matches the `--project-name=pro_app`
     the workflow passes to `flutter create` - check
     `android/app/build.gradle`'s `applicationId` after a build if unsure).
   - SHA-1 fingerprint: `CC:73:AE:81:85:87:2B:9B:84:A5:83:54:1C:BF:5C:BA:C9:64:F4:0A`
     (this is fixed now - no need to regenerate it after future builds,
     as long as the same `DEBUG_KEYSTORE_BASE64` secret stays in place).
4. Push to `main` (or re-run the workflow) to get a build signed with the
   stable keystore, then use **Settings → Backup & Restore → Connect
   Google Drive** in the app - no code changes needed, `google_sign_in`
   picks up the registered client automatically.

   Status: Google Cloud project `pro-app-drive-backup` is set up - Drive
   API enabled, OAuth consent screen configured (Testing, with
   ayyanarsripath@gmail.com as a test user), and the Android OAuth client
   above is created and matches this SHA-1. This commit's push is the
   "fresh build" step, so the very next CI run already picks up the
   stable keystore and this registered client.

### If you build locally on your own machine

1. Go to https://console.cloud.google.com → create a project.
2. Enable the **Google Drive API**.
3. Create an **OAuth 2.0 Client ID** of type "Android", using this app's
   package name (check `android/app/build.gradle`'s `applicationId`,
   `com.example.pro_app` or `com.example.professional_mobiles` depending
   on what you passed to `flutter create --project-name=...`) and your own
   local keystore's SHA-1 fingerprint
   (`keytool -list -v -keystore <your-keystore>`) - by default this is
   `~/.android/debug.keystore` (alias `androiddebugkey`, password
   `android` for both).
4. That's it - no code changes needed. `google_sign_in` picks up the
   client automatically. Use **Settings → Backup & Restore → Connect
   Google Drive** in the app.

## 6. What's inside (maps to your spec)

**Base app:** offline SQLite database, customers + full history, service
job cards with photos/status pipeline/warranty/payments/delivery, spare
parts & accessories inventory with low-stock alerts, sales billing, 2nd
hand mobile purchase → repair → sale pipeline, suppliers & purchases,
expenses, warranty claims, returns (accessories/2nd hand/spare parts),
Admin PIN + staff permissions, manual/weekly/Google Drive backup + restore.

**This module's additions:**
- Full category-wise Profit & Loss engine (Service / Accessories / Spare
  Parts / 2nd Hand / Other Sales / Expenses), transaction-ledger based so
  historical numbers never drift when stock is adjusted later.
- Per-service internal costing hidden from the customer bill, admin-only.
- 2nd hand realized-vs-potential profit split (unsold stock's expected
  profit is never counted as real profit).
- P&L Dashboard: Today / This Week / This Month / Previous Month / Custom
  range, category cards, revenue chart, summary table, Month-End Report,
  PDF export/print.
- Premium redesigned Service Job Card screen with quick actions (Edit, Add
  Payment, Change Status, Print, WhatsApp, SMS, Delivery, Warranty Claim),
  a big Final/Paid/Balance summary card with a "PAYMENT PENDING" flag, and
  status colour-coding across Received → Checking → Repairing → Part
  Pending → Ready → Delivered → Warranty → Cancelled.
- Premium A5 bills (Service Job Card, Sales Bill, 2nd Hand Sales Bill) with
  your logo printed in a black-and-white-friendly form (per your request -
  it'll look right on a plain B/W printer), boxed sections, and the Tamil
  return-policy footer + signature lines on the service bill.

## 7. Honest limitations

- **Weekly auto-backup** runs when the app is opened (checks "has it been
  7+ days"), not via a true background OS job - Android kills background
  tasks aggressively without extra plugins, so this keeps things reliable
  without adding complexity. Manual backup is always one tap away.
- **Google Drive backup** needs the one-time setup in section 5 - Google
  requires every app to bring its own OAuth client, this can't be
  pre-baked in for you.
- **"Other Sales"** is intentionally a quick manual entry (button on the
  P&L Dashboard) rather than a full inventory module, since it's meant to
  catch one-off income that doesn't fit the other categories.
- This project wasn't compiled/run in the environment it was written in
  (see section 1), so please do a quick pass through the main flows
  (create a service, take a payment, sell an accessory, buy/sell a 2nd
  hand phone, check the P&L dashboard) after your first build and tell me
  if anything needs a fix - happy to patch it.
