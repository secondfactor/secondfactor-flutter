/// secondfactor.ai for Flutter: the client half of hosted verification.
///
/// secondfactor.ai verifies a phone number on its own hosted page, much like
/// Stripe Checkout. Your server creates a verification session with its API
/// key (the `secondfactor` package on npm or PyPI) and gets back the page's
/// `url`. This library does the one thing left for the app:
///
/// ```dart
/// // Open our page and wait for the user to come back.
/// final back = await SecondFactor.verify(url: url, returnUrl: returnUrl);
///
/// // Send back.returnToken to your server, which passes it to verifySession.
/// ```
///
/// On iOS the page opens in an `ASWebAuthenticationSession` sheet, and on
/// Android in a Custom Tab. It never calls the secondfactor.ai API and never
/// holds a key, a phone number or a code. Nothing it reports is proof that a
/// number was verified: only your server's `verifySession` call is.
library;

import 'package:flutter/services.dart';

/// The two parameters the hosted page adds to your return URL.
class VerificationReturn {
  /// Creates a return value. Apps normally get one from
  /// [SecondFactor.verify] or [SecondFactor.parseVerificationReturn].
  const VerificationReturn(this.sessionId, this.returnToken);

  /// `sf_session_id`. Tells you which stored session the user came back
  /// from. Anyone can edit a URL, so your server must always confirm the
  /// session ID it stored, never this one.
  final String sessionId;

  /// `sf_return_token`. Present only when the user verified; null when they
  /// canceled on the page, ran out of attempts or the session expired. Send it to your server,
  /// which passes it to `verifySession`. It works once.
  final String? returnToken;

  @override
  bool operator ==(Object other) =>
      other is VerificationReturn && other.sessionId == sessionId && other.returnToken == returnToken;

  @override
  int get hashCode => Object.hash(sessionId, returnToken);

  // The return token is left out so that logging this object, or showing it
  // in a crash report, never leaks a token that can still be redeemed.
  @override
  String toString() =>
      'VerificationReturn(sessionId: $sessionId, returnToken: ${returnToken == null ? 'null' : '[redacted]'})';
}

/// Why [SecondFactor.verify] did not return.
enum SecondFactorError {
  /// `url` is not a hosted verification page. Pass the `url` your server
  /// received from `createSession`, unchanged.
  notAVerificationPage,

  /// `returnUrl` is not an `https://` URL with a host.
  invalidReturnUrl,

  /// The user closed the page before finishing. Nothing was verified.
  canceled,

  /// The page returned to a URL without `sf_session_id`.
  missingReturnParameters,

  /// The page could not be shown: there is no activity or window to show it
  /// from, the device has no browser, or the iOS version is older than 17.4.
  couldNotStart,
}

/// Thrown by [SecondFactor.verify]. [error] says why.
class SecondFactorException implements Exception {
  /// Creates an exception for [error], with a human-readable [message].
  const SecondFactorException(this.error, this.message);

  /// Why the verification did not finish.
  final SecondFactorError error;

  /// A description for logs. Not meant to be shown to the user as is.
  final String message;

  @override
  String toString() => 'SecondFactorException(${error.name}): $message';
}

/// The client half of secondfactor.ai hosted verification.
abstract final class SecondFactor {
  /// This package's version. Bump it together with `pubspec.yaml` and
  /// `CHANGELOG.md`.
  static const version = '0.1.0';

  static const _channel = MethodChannel('ai.secondfactor/verify');

  static const _sessionParam = 'sf_session_id';
  static const _tokenParam = 'sf_return_token';

  // Plain http:// is accepted only for these hosts, so a local verify page
  // can be used in development. `*.localhost` always resolves to the device
  // itself.
  static const _loopbackHosts = {'localhost', '127.0.0.1', '[::1]'};

  static final _visibleAscii = RegExp(r'^[\x21-\x7e]+$');
  static final _pageUrl = RegExp(
    r'^([a-z][a-z0-9+.-]*)://([^/?#\\@]+)[^#\\]*#vst_[A-Za-z0-9_-]+$',
    caseSensitive: false,
  );
  static final _authority = RegExp(r'^(\[[0-9a-f:.]+\]|[a-z0-9._-]+)(?::[0-9]{1,5})?$', caseSensitive: false);

  /// Opens the hosted verification page and waits for the user to come back.
  ///
  /// On iOS the page opens in an `ASWebAuthenticationSession` sheet, which
  /// needs iOS 17.4 or later and closes by itself when the page sends the
  /// user to [returnUrl]. On Android it opens in a Custom Tab (or the default
  /// browser), and the return arrives as an App Link. Both need the set-up
  /// described in the README, or the return never reaches the app.
  ///
  /// [url] must be the `url` your server received from `createSession`. It
  /// is checked with [isVerificationPageUrl] before anything opens, so a URL
  /// that reached the app some other way is refused rather than opened.
  ///
  /// [returnUrl] must be the same `https://` URL your server passed to
  /// `createSession` as `returnUrl`. Only its host and path are used: a
  /// return to any other URL is not taken as the end of the verification.
  ///
  /// Returns the parameters the page came back with. Check
  /// [VerificationReturn.returnToken]: null means the user did not verify.
  ///
  /// Throws a [SecondFactorException] for bad arguments, when the user closes
  /// the page, when the return carries no session, or when the page cannot be
  /// shown. Any other error the platform reports is thrown unchanged, as a
  /// [PlatformException].
  static Future<VerificationReturn> verify({required String url, required String returnUrl}) async {
    if (!isVerificationPageUrl(url)) {
      throw const SecondFactorException(
        SecondFactorError.notAVerificationPage,
        'url is not a secondfactor.ai verification page. Pass the url your server got from createSession.',
      );
    }
    final back = Uri.tryParse(returnUrl);
    if (back == null || back.scheme.toLowerCase() != 'https' || back.host.isEmpty) {
      throw const SecondFactorException(
        SecondFactorError.invalidReturnUrl,
        'returnUrl must be the https:// URL your server passed to createSession.',
      );
    }

    final String? returned;
    try {
      returned = await _channel.invokeMethod<String>('verify', {
        'url': url,
        'host': back.host,
        'path': back.path.isEmpty ? '/' : back.path,
      });
    } on PlatformException catch (e) {
      final error = SecondFactorError.values.asNameMap()[e.code];
      if (error == null) rethrow;
      throw SecondFactorException(error, e.message ?? error.name);
    }

    final found = parseVerificationReturn(returned);
    if (found == null) {
      throw const SecondFactorException(
        SecondFactorError.missingReturnParameters,
        'The verification page returned without sf_session_id.',
      );
    }
    return found;
  }

  /// Reads `sf_session_id` and `sf_return_token` from any URL string.
  ///
  /// [verify] calls this for you. Call it yourself when the return reaches
  /// your app another way, for example as a deep link after Android ended
  /// the app's process while the page was open. Nothing here is checked
  /// against secondfactor.ai: your server does that when it confirms the
  /// session.
  ///
  /// Returns null when [url] is null or carries no session ID.
  /// [VerificationReturn.returnToken] is null when the user did not verify.
  static VerificationReturn? parseVerificationReturn(String? url) {
    if (url == null) return null;
    final query = url.split('#').first;
    final start = query.indexOf('?');
    if (start == -1) return null;
    final params = <String, String>{};
    for (final pair in query.substring(start + 1).split('&')) {
      final separator = pair.indexOf('=');
      final key = _decode(separator == -1 ? pair : pair.substring(0, separator));
      // The first value wins. The hosted page replaces any parameter of the
      // same name rather than adding a second, so a repeat did not come from
      // it.
      if (key != null && !params.containsKey(key)) {
        params[key] = _decode(separator == -1 ? '' : pair.substring(separator + 1)) ?? '';
      }
    }
    final sessionId = params[_sessionParam];
    if (sessionId == null || sessionId.isEmpty) return null;
    final token = params[_tokenParam];
    return VerificationReturn(sessionId, token == null || token.isEmpty ? null : token);
  }

  /// Whether [url] has the shape of a hosted verification page: `https://`
  /// (or plain `http://` on a loopback host), no user name or password, and
  /// the session's client token (`#vst_…`) in the fragment, where the page
  /// reads it.
  ///
  /// It is matched by hand rather than with [Uri], which accepts almost any
  /// string and would let schemes such as `intent:` through.
  static bool isVerificationPageUrl(String url) {
    if (!_visibleAscii.hasMatch(url)) return false;
    final parts = _pageUrl.firstMatch(url);
    if (parts == null) return false;
    final authority = _authority.firstMatch(parts.group(2)!);
    if (authority == null) return false;
    final scheme = parts.group(1)!.toLowerCase();
    final host = authority.group(1)!.toLowerCase();
    return scheme == 'https' || (scheme == 'http' && (_loopbackHosts.contains(host) || host.endsWith('.localhost')));
  }

  /// A query-string component decoded, or null when it is malformed.
  static String? _decode(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }
}
