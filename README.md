# secondfactor.ai for Flutter

The client half of [secondfactor.ai](https://secondfactor.ai) hosted
verification for Flutter apps on iOS and Android. Your users verify their phone
number on our page, much like Stripe Checkout; this package opens that page and
returns the result when the user comes back to your app.

- **iOS:** the page opens in an `ASWebAuthenticationSession` sheet that closes
  by itself on return.
- **Android:** the page opens in a Custom Tab, and the return arrives as an App
  Link.

No dependencies beyond Flutter.

This package runs on the **user's device**. It never calls the secondfactor.ai
API, and never holds your API key, a phone number or a code. Your server holds
the key and uses a server library:
[`secondfactor`](https://github.com/secondfactor/secondfactor-node) on npm or
[`secondfactor`](https://github.com/secondfactor/secondfactor-python) on PyPI.

> **Act on the result on your server.** What this package reads from a URL is
> not proof of anything: anyone can craft a link that opens your app. Your
> server confirms the session it stored, once, and that answer is the proof.

## Requirements

- iOS 17.4 or later for `SecondFactor.verify`, which uses
  `ASWebAuthenticationSession` with an `https://` callback. The package builds
  for older versions, where `verify` throws `couldNotStart`.
- Android 7.0 (API 24) or later.
- Flutter 3.10 or later. Tested with Flutter 3.44.

## Install

```bash
flutter pub add secondfactor
```

## Set up

The return URL must be an `https://` URL on one of the return origins listed
under **Settings → Hosted verification** in the secondfactor.ai dashboard.
Custom URL schemes such as `myapp://` are not accepted, because any app can
claim them. The examples use `https://app.example.com/verified`.

### iOS

1. Give your app the **Associated Domains** capability with
   `webcredentials:app.example.com`.
2. Serve `https://app.example.com/.well-known/apple-app-site-association`
   listing your app under `webcredentials`:

   ```json
   { "webcredentials": { "apps": ["TEAMID.com.example.yourapp"] } }
   ```

Without both, iOS will not hand the return back to your app and the sheet will
not close by itself.

### Android

1. **Claim the URL** in `android/app/src/main/AndroidManifest.xml`, on your
   Flutter activity, and change its `launchMode` from `singleTop` to
   `singleTask`:

   ```xml
   <activity
       android:name=".MainActivity"
       android:launchMode="singleTask"
       ...>
       <intent-filter android:autoVerify="true">
           <action android:name="android.intent.action.VIEW" />
           <category android:name="android.intent.category.DEFAULT" />
           <category android:name="android.intent.category.BROWSABLE" />
           <data android:scheme="https" android:host="app.example.com" android:path="/verified" />
       </intent-filter>
   </activity>
   ```

   `singleTask` matters. The Custom Tab runs in your app's task, on top of your
   activity. With `singleTask`, the return closes the tab and reaches the
   running activity. With Flutter's default `singleTop`, Android starts a
   second copy of your app on top of the tab, and `verify` never returns.

2. **Prove you own the domain** by serving
   `https://app.example.com/.well-known/assetlinks.json`:

   ```json
   [{
     "relation": ["delegate_permission/common.handle_all_urls"],
     "target": {
       "namespace": "android_app",
       "package_name": "com.example.app",
       "sha256_cert_fingerprints": ["AB:CD:…"]
     }
   }]
   ```

   Use the SHA-256 fingerprint of the key your release builds are signed with
   (Play Console → **Test and release → App signing**), and add your debug
   key's fingerprint too if you want links to work in debug builds. Until the
   domain is verified, Android opens the return URL in the browser instead of
   your app. Check the state with
   `adb shell pm get-app-links com.example.app`.

## How it fits together

1. **Your server** creates a session for the number it wants verified, keeps
   its `sid`, and gives the page's `url` to your app:

   ```js
   // Node, with the `secondfactor` package.
   const session = await sf.createSession({
     to: user.phone,
     returnUrl: "https://app.example.com/verified",
   });
   user.pendingSid = session.sid;
   res.json({ url: session.url });
   ```

2. **Your app** opens our page and waits for the user to come back:

   ```dart
   import 'package:secondfactor/secondfactor.dart';

   final url = await api.startVerification(); // the `url` from step 1
   final back = await SecondFactor.verify(
     url: url,
     returnUrl: 'https://app.example.com/verified',
   );
   ```

   We send the code, the user types it on our page, and we send them back.

3. **Your app** hands the return token to your server:

   ```dart
   final token = back.returnToken;
   if (token != null) {
     await api.finishVerification(token); // your server calls verifySession
   } else {
     // The user ran out of attempts or the session expired.
   }
   ```

   `verify` throws a `SecondFactorException` when the user closes the page
   instead; its `error` is `SecondFactorError.canceled`.

4. **Your server** confirms the session it stored, once, and acts on that:

   ```js
   const { phone } = await sf.verifySession(user.pendingSid, req.body.returnToken);
   ```

## Usage

A complete verification, from asking your server for the page to telling the
user how it went. `MyApi` stands for your app's own client for your server,
with the two endpoints from the steps above.

```dart
import 'package:flutter/material.dart';
import 'package:secondfactor/secondfactor.dart';

/// Your app's client for your own server.
abstract interface class MyApi {
  /// Asks your server to call `createSession`, and returns the page's `url`.
  Future<String> startVerification();

  /// Hands the return token to your server, which calls `verifySession`.
  Future<void> finishVerification(String returnToken);
}

/// The same `https://` URL your server passes to `createSession`.
const returnUrl = 'https://app.example.com/verified';

/// Runs one verification and returns a message to show the user.
Future<String> verifyPhone(MyApi api) async {
  final url = await api.startVerification();

  final VerificationReturn back;
  try {
    back = await SecondFactor.verify(url: url, returnUrl: returnUrl);
  } on SecondFactorException catch (e) {
    switch (e.error) {
      case SecondFactorError.canceled:
        return 'Verification canceled.';
      case SecondFactorError.couldNotStart:
        return 'The verification page could not be opened.';
      case SecondFactorError.notAVerificationPage:
      case SecondFactorError.invalidReturnUrl:
      case SecondFactorError.missingReturnParameters:
        // The app and the server disagree about a URL. That is a bug to
        // fix, not something the user can act on, so let it reach your
        // error reporting.
        rethrow;
    }
  }

  final token = back.returnToken;
  if (token == null) {
    // The user ran out of attempts, or the session expired.
    return 'Your number was not verified. Please try again.';
  }
  await api.finishVerification(token);
  return 'Your number is verified.';
}

/// A button that runs [verifyPhone] and shows the result.
class VerifyPhoneButton extends StatefulWidget {
  const VerifyPhoneButton({super.key, required this.api});

  final MyApi api;

  @override
  State<VerifyPhoneButton> createState() => _VerifyPhoneButtonState();
}

class _VerifyPhoneButtonState extends State<VerifyPhoneButton> {
  bool _busy = false;

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      final message = await verifyPhone(widget.api);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _busy ? null : _verify,
      child: const Text('Verify phone number'),
    );
  }
}
```

The button is disabled while a verification is open. Starting a second one
would end the first as `canceled`.

## API

### `SecondFactor.verify({required String url, required String returnUrl})`

Opens the hosted page and completes when the page sends the user to
`returnUrl`. Returns a `VerificationReturn`.

`url` must be the `url` your server got from `createSession`; anything else
throws `notAVerificationPage` and is not opened. `returnUrl` must be the same
`https://` URL your server passed as `returnUrl`; only its host and path are
matched. Starting a second verification while one is open ends the first as
`canceled`.

On iOS the sheet uses an ephemeral browser session, so it shares no cookies
with Safari and keeps none afterwards.

### `SecondFactor.parseVerificationReturn(String? url)`

Reads `sf_session_id` and `sf_return_token` from any URL, or returns null when
there is no session ID. `verify` calls it for you. Call it yourself if the
return reaches your app another way. On Android this happens when the system
ends your app's process while the page is open: the app then starts afresh
with the return URL as its deep link, and the pending `verify` call no longer
exists.

### `SecondFactor.isVerificationPageUrl(String url)`

Whether `url` has the shape of a hosted page: `https://` (plain `http://` only
for `localhost`, `127.0.0.1`, `[::1]` and `*.localhost`), no user name or
password, and a `#vst_…` fragment.

### `VerificationReturn`

- `sessionId`: tells you which stored session the user came back from. Your
  server must always confirm the `sid` it stored, never this one.
- `returnToken`: present only when the user verified. It works once.

Its `toString()` leaves out the return token, so logging it never leaks a
token that can still be redeemed.

### `SecondFactorException`

`error` is one of:

| `SecondFactorError`       | Meaning                                                                 |
|---------------------------|-------------------------------------------------------------------------|
| `notAVerificationPage`    | `url` is not a hosted page. Pass the server's `url` unchanged.          |
| `invalidReturnUrl`        | `returnUrl` is not `https://` with a host.                              |
| `canceled`                | The user closed the page. Nothing was verified.                         |
| `missingReturnParameters` | The page returned without `sf_session_id`.                              |
| `couldNotStart`           | No activity, window or browser to show the page, or iOS older than 17.4. |

Any other platform error is thrown unchanged, as a `PlatformException`.

## Example

[`example/`](example) is a one-screen app that calls `verify` with a page URL
you paste in.

## Development

```bash
flutter test      # URL validation, return parsing and the platform channel
flutter analyze
```

To build the example for iOS, check the repository out into a directory named
`secondfactor`. Flutter's Swift Package Manager integration names the plugin
after its directory, and Xcode refuses to resolve packages when that name
differs from the package's own.

## License

MIT
