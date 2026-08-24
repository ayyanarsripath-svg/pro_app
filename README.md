# Professional Mobiles & Laptop Service - Business Manager

Offline-first Android app (Flutter) for a mobile/laptop repair shop that also
buys and sells 2nd hand phones: customers, service job cards, spare parts &
accessories inventory, sales billing, 2nd hand mobile purchase/sale,
suppliers & purchases, a daily supplier-order WhatsApp reminder, expenses, a
full Profit & Loss engine, A5 bill printing with your logo, staff PIN +
permissions, and local/Google Drive backup. No server, no internet required
for daily use.

---

## 1. Why you're building this yourself

This project was written in a sandboxed environment that cannot reach
Google's Flutter/Dart package servers, so it could not be compiled into a
ready `.apk` there. Everything else is done: real, organized Dart source, a
complete offline SQLite schema, and every screen described in the spec.
Turning it into an installable app takes about 10 minutes with the steps
below.

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

# 3. Add these permissions to android/app/src/main/AndroidManifest.xml,
#    inside the <manifest> tag (above <application>):
#    <uses-permission android:name="android.permission.CAMERA"/>
#    <uses-permission android:name="android.permission.INTERNET"/>
#    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
#    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
#    (CAMERA is for service/2nd-hand phone photos; INTERNET is only used for
#    the optional Google Drive backup; POST_NOTIFICATIONS + SCHEDULE_EXACT_
#    ALARM are what let the Supplier Order reminder fire at the exact time
#    you set, even Android 13+/12+ - without them the OS silently blocks or
#    delays it. Only needed if you're building locally - if you also build
#    via a GitHub Actions workflow, make sure its manifest-patching step
#    adds these same two lines.)

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

**After installing:** open the app once and allow the "Notifications" and
"Alarms & reminders" prompts when asked (needed for Supplier Order
reminders - see section 8). On Xiaomi/Vivo/Oppo/OnePlus phones, also turn
off battery optimisation for this app (Settings → Apps → Professional
Mobiles → Battery → "No restrictions") - those phones aggressively kill
scheduled alarms otherwise, which is the single most common reason a
reminder "just doesn't go off" on Android.

## 4. First launch

The very first time the app opens it asks you to create the **Admin
account** (name + PIN). That PIN gates all profit/cost figures everywhere
in the app (spec section 28) - customer-facing bills never show purchase
cost, spare part cost, or profit regardless of who's logged in. Add staff
accounts and pick exactly what each one can see under **Settings → Staff &
Permissions**.

## 5. Google Drive backup setup (optional - skip if you don't need it)

Everything works fully offline without this.

**If you build locally on your own machine:**
1. Go to https://console.cloud.google.com → create a project.
2. Enable the **Google Drive API**.
3. Create an **OAuth 2.0 Client ID** of type "Android", using this app's
   package name (check `android/app/build.gradle`'s `applicationId`,
   `com.example.pro_app` or `com.example.professional_mobiles` depending on
   what you passed to `flutter create --project-name=...`) and your own
   local keystore's SHA-1 fingerprint (`keytool -list -v -keystore
   <your-keystore>` - by default `~/.android/debug.keystore`, alias
   `androiddebugkey`, password `android` for both).
4. That's it - no code changes needed. `google_sign_in` picks up the client
   automatically. Use **Settings → Backup & Restore → Connect Google
   Drive** in the app, then **Choose Folder** to pick (or create) exactly
   which Drive folder backups go into - the app defaults to creating a
   normal, visible "Professional Mobiles Backups" folder in your own My
   Drive if you skip that step (never a hidden folder).

**If you build APKs via a GitHub Actions workflow:** every APK built by CI
must be signed with the *same* keystore every time, or its SHA-1
fingerprint changes on every build and silently breaks Google sign-in
(`DEVELOPER_ERROR` / "sign-in cancelled" every time you rebuild). Restore a
stable keystore from a repository secret (`DEBUG_KEYSTORE_BASE64`) instead
of letting the workflow generate a fresh throwaway one, then register that
keystore's SHA-1 as the OAuth client's fingerprint in Google Cloud Console
and keep it there. If sign-in that used to work suddenly starts failing
with `ApiException: 10` / `DEVELOPER_ERROR` after a rebuild, that mismatch
- CI keystore secret changed without updating the registered SHA-1 - is the
first thing to check; the in-app error message (Settings → Backup & Restore
→ Connect Google Drive) now shows this diagnosis directly when sign-in
fails, instead of a bare "cancelled".

Also check **OAuth consent screen → Publishing status** in Google Cloud
Console: while it stays in "Testing", every sign-in grant is a test-user
grant and Google expires those refresh tokens after 7 days regardless of
anything the app does - which looks exactly like "have to sign in again"
every week or two. Click "Publish App" to move it to "In production" - for
an app used only by you (already a project owner / listed test user), this
is a one-time, ~30-second fix that needs no Google review.

## 6. What's inside (maps to your spec)

**Base app:** offline SQLite database, customers + full history, service
job cards with photos/status pipeline/warranty/payments/delivery, spare
parts & accessories inventory with low-stock alerts, sales billing, 2nd
hand mobile purchase → repair → sale pipeline, suppliers & purchases,
expenses, warranty claims, returns (accessories/2nd hand/spare parts),
Admin PIN + staff permissions, manual/daily-or-weekly/Google Drive backup +
restore.

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
  your logo printed in a black-and-white-friendly form, boxed sections, and
  the Tamil return-policy footer + signature lines on the service bill.
- **Supplier Orders (Daily Order reminder)** - see section 8.

## 7. Honest limitations

- **Automatic backup** (daily by default, switchable to weekly in Settings
  → Backup & Restore) runs when the app is opened, not via a true
  background OS job - Android kills background tasks aggressively without
  extra plugins, so this keeps things reliable without adding complexity.
  Manual backup is always one tap away, and "Save Backup To..." lets you
  put a copy somewhere you can actually browse to (see section 8's sibling
  note on the private-storage folder for why "Backup Now" alone can look
  invisible).
- **Supplier Order reminders** re-arm every time the app is opened (see
  section 8) - a reboot that happens while the app stays closed for a long
  stretch means the reminder won't fire until you next open the app. Once
  opened, anything whose time already passed fires immediately as a
  catch-up, so nothing is silently skipped - it just isn't a true
  background service.
- **Google Drive backup** needs the one-time setup in section 5 - Google
  requires every app to bring its own OAuth client, this can't be
  pre-baked in for you.
- **"Other Sales"** is intentionally a quick manual entry (button on the
  P&L Dashboard) rather than a full inventory module, since it's meant to
  catch one-off income that doesn't fit the other categories.
- This project wasn't compiled/run in the environment it was written in
  (see section 1), so please do a quick pass through the main flows after
  your first build and report anything that needs a fix.

## 8. Supplier Orders - the daily order / WhatsApp auto-send reminder

Flow: **Settings drawer → Supplier Orders → Quick Order**.

1. Type what needs to be ordered (free text - item list, quantities,
   whatever you'd normally tell the supplier).
2. Pick a saved supplier or type a name + WhatsApp number.
3. Set the time it should go out, optionally "Repeat every day at this
   time" for a standing daily order.
4. Save. At that exact time you get a notification. Tap it and a bottom
   sheet opens with the order PDF already generated and two buttons:
   **"Open WhatsApp Chat"** (opens straight to the supplier's chat with
   your message pre-filled) and **"Share Order PDF"** (Android's share
   sheet with the PDF already attached - pick WhatsApp, pick the chat if it
   isn't offered automatically, tap Send).

**Why it can't be fully one-tap automatic:** Android and WhatsApp
deliberately don't allow any app to both pre-attach a file *and*
pre-select the exact chat it goes to in one step - that combination is
blocked for anti-spam reasons on Meta's side, not something this app can
route around. The two-button flow above is the closest a normal Android
app is allowed to get: correct recipient in one tap, correct file in the
next, Send is always the one manual action left to you (which also
matches what you asked for - a reminder to tap Send yourself, not a
message that goes out with nobody checking it first).

**Why the old "set 2:42, fires 2:41 / doesn't fire at all" symptom won't
recur:** the reminder is scheduled with the phone's real timezone properly
initialised (a very common Flutter bug is silently scheduling against UTC
instead), using Android's *exact* alarm mode so Doze/battery-saving
doesn't push the time around, with the two permissions from section 3
requested up front, and with a catch-up check every time the app opens so
a reminder that was missed for any reason (phone off, alarm cleared by a
reboot, aggressive battery optimisation on some brands) still surfaces the
moment you next open the app instead of silently vanishing.
