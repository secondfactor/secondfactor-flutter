# secondfactor example

A one-screen app around `SecondFactor.verify`. Paste the `url` your server got
from `createSession`, set the return URL your server passed as `returnUrl`, and
press **Verify**.

The return only reaches the app once the set-up in the
[package README](../README.md#set-up) is done for your own domain: the App Link
in `android/app/src/main/AndroidManifest.xml` and the Associated Domains
entitlement on iOS both use the placeholder `app.example.com`.

```bash
flutter run
```
