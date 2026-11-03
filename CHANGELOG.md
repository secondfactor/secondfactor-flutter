# Changelog

All notable changes to the `secondfactor` Flutter package are recorded here.
The project follows [Semantic Versioning](https://semver.org/).

## 0.1.0 — 2026-11-02

First release.

### Added

- `SecondFactor.verify(url:, returnUrl:)` opens the hosted verification page,
  in an `ASWebAuthenticationSession` on iOS and a Custom Tab on Android, and
  returns the session ID and return token the page came back with. A URL that
  is not a verification page is refused before anything opens.
- `SecondFactor.parseVerificationReturn(url)` reads `sf_session_id` and
  `sf_return_token` from any URL.
- `SecondFactor.isVerificationPageUrl(url)`.
- `VerificationReturn.toString()` leaves out the return token.
