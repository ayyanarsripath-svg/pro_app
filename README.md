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
# never touches the lib/ source that's already here):
flutter create --platforms=android .

# 3. Add this permission to android/app/src/main/AndroidManifest.xml,
# inside the <manifest> tag (above <application>):
# <uses-permission android:name="android.permission.INTERNET"/>
# (INTERNET is only used for the optional Google Drive backup - the rest
# of the app is 100% offline. Service/2nd-hand-phone photo capture does
# NOT need a CAMERA permission declared - image_picker delegates to the
# phone's own Camera app via an Intent, and deliberately declaring CAMERA
# would only add an unnecessary extra runtime permission prompt.) Only
# needed if you're building locally - the GitHub Actions workflow
# (.github/workflows/build-apk.yml) already does this step for you
# automatically, every build.

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
   - SHA-1 fingerprint: `06:96:3D:AB:58:CE:FF:61:A2:58:CE:4B:ED:B3:6D:D7:3C:C7:A9:0E`
     (this is fixed now - no need to regenerate it after future builds,
     as long as the same `DEBUG_KEYSTORE_BASE64` secret stays in place -
     re-check it any time against the "Print release APK signing SHA-1"
     step's log on the latest CI build if sign-in ever starts failing
     again, in case the secret was ever replaced).
4. Push to `main` (or re-run the workflow) to get a build signed with the
   stable keystore, then use **Settings → Backup & Restore → Connect
   Google Drive** in the app - no code changes needed, `google_sign_in`
   picks up the registered client automatically.

**⚠️ Action needed (this is almost certainly why "select account" keeps
failing with "sign-in cancelled" / "16: ... reauth failed" every time
the app is updated):** two separate things to check in
https://console.cloud.google.com for project `pro-app-drive-backup`:
1. **APIs & Services → Credentials** - open the Android OAuth 2.0
   Client ID and confirm its SHA-1 exactly matches the one above
   (`06:96:3D:AB:...`). A previous version of this doc listed a
   *different* SHA-1 (`E5:90:16:89:...`) as "verified working" - if the
   `DEBUG_KEYSTORE_BASE64` secret was ever regenerated since then
   without also updating this registration, sign-in would fail on
   every device using a current build, which matches exactly what's
   being reported. Update it to the current SHA-1 if it doesn't match.
2. **APIs & Services → OAuth consent screen → Publishing status** -
   while this stays in **Testing**, every sign-in Google grants is a
   *test-user* grant, and Google expires those refresh tokens after
   **7 days** regardless of anything this app does - which shows up as
   exactly this "have to sign in again" cycle roughly every week or
   two. Click **"Publish App"** to move it to **In production**. For
   an app used only by you (the account is already the project owner/
   a listed test user), this does not require Google's review or
   trigger any "unverified app" block for you - it just removes the
   7-day expiry. This is a one-time, ~30-second fix.

Status: Drive API enabled. Backups go to a normal, visible
"Professional Mobiles Backups" folder in your own Drive (not the
hidden App Data folder). A brand new, independent, verified backup file
is created every day (never overwritten in place), timed to an exact
~10 PM alarm with a WorkManager fallback/retry - see `BackupService` and
`background_tasks.dart` in `lib/core/services/`.

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
Admin PIN + staff permissions, manual local backup + daily automatic
Google Drive backup/restore.

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

- **Daily Google Drive backup** fires from an exact ~10 PM alarm
  (`android_alarm_manager_plus`), with a WorkManager fallback/retry and an
  app-open catch-up so a missed day never stays missed - see
  `BackupService.runDailyGoogleDriveBackupIfDue`. It needs the one-time
  setup in section 5 - Google requires every app to bring its own OAuth
  client, this can't be pre-baked in for you.
- **"Other Sales"** is intentionally a quick manual entry (button on the
  P&L Dashboard) rather than a full inventory module, since it's meant to
  catch one-off income that doesn't fit the other categories.
- This project wasn't compiled/run in the environment it was written in
  (see section 1), so please do a quick pass through the main flows
  (create a service, take a payment, sell an accessory, buy/sell a 2nd
  hand phone, check the P&L dashboard) after your first build and tell me
  if anything needs a fix - happy to patch it.
