// The parts of the library that decide what may be opened, what a return URL
// says, and how the platform's answer reaches the caller. The URL cases are
// the same as the JavaScript, Kotlin and Swift libraries' tests.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondfactor/secondfactor.dart';

const page = 'https://verify.secondfactor.ai/#vst_Qm9yZWFsaXMgb2YgdGhlIG5vcnRo-_x';
const returnUrl = 'https://app.example.com/verified';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isVerificationPageUrl', () {
    for (final url in [
      page,
      'https://uat-verify.secondfactor.ai/#vst_abc',
      'HTTPS://Verify.SecondFactor.ai:443/s?x=1#vst_A-b_9',
      'http://verify.localhost:5175/#vst_abc',
      'http://localhost:5175/#vst_abc',
      'http://127.0.0.1:5175/#vst_abc',
      'http://[::1]:3000/fake-verify?sid=VSN1#vst_demo',
    ]) {
      test('accepts $url', () => expect(SecondFactor.isVerificationPageUrl(url), isTrue));
    }

    for (final url in [
      'javascript:alert(document.cookie)//#vst_abc',
      'data:text/html,<script>alert(1)</script>#vst_abc',
      'intent://verify.secondfactor.ai/#Intent;scheme=https;end#vst_abc',
      'http://verify.secondfactor.ai/#vst_abc', // plain http off a loopback host
      'https://verify.secondfactor.ai/', // no client token
      'https://verify.secondfactor.ai/#vsr_abc', // a return token, not a client token
      'https://user:pass@verify.secondfactor.ai/#vst_abc',
      r'https://evil.example\@verify.secondfactor.ai/s#vst_abc',
      'http://localhost.evil.example/s#vst_abc',
      '//verify.secondfactor.ai/#vst_abc',
      'https://verify.secondfactor.ai/#vst_abc def',
      '',
    ]) {
      test('refuses "$url"', () => expect(SecondFactor.isVerificationPageUrl(url), isFalse));
    }
  });

  group('parseVerificationReturn', () {
    test('reads the session ID and the return token', () {
      expect(
        SecondFactor.parseVerificationReturn(
          'https://app.example.com/verified?step=2&sf_session_id=VSN26H7K3MQ2XWZ8RT4&sf_return_token=vsr_abc-_9#top',
        ),
        const VerificationReturn('VSN26H7K3MQ2XWZ8RT4', 'vsr_abc-_9'),
      );
    });

    test('has no return token when the user did not verify', () {
      expect(
        SecondFactor.parseVerificationReturn('https://app.example.com/back?sf_session_id=VSN1&sf_return_token='),
        const VerificationReturn('VSN1', null),
      );
    });

    for (final url in [
      'https://app.example.com/verified',
      'https://app.example.com/verified?sf_session_id=',
      'https://app.example.com/verified?sf_return_token=vsr_abc',
      'https://app.example.com/verified#?sf_session_id=VSN1',
      '',
      null,
    ]) {
      test('is null for "$url"', () => expect(SecondFactor.parseVerificationReturn(url), isNull));
    }

    test('decodes and keeps the first of a repeated parameter', () {
      expect(
        SecondFactor.parseVerificationReturn(
          'https://app.example.com/v?sf_session_id=VSN%201&sf_return_token=vsr_a&sf_return_token=vsr_b&bad=%E0%A4%A',
        ),
        const VerificationReturn('VSN 1', 'vsr_a'),
      );
    });

    test('never prints the return token', () {
      expect(const VerificationReturn('VSN1', 'vsr_secret').toString(), isNot(contains('vsr_secret')));
    });
  });

  group('verify', () {
    const channel = MethodChannel('ai.secondfactor/verify');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    void answer(Object? Function(MethodCall call) handler) {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });
    }

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Matcher failsWith(SecondFactorError error) =>
        throwsA(isA<SecondFactorException>().having((e) => e.error, 'error', error));

    test('passes the page and the return host and path, and parses the answer', () async {
      answer((_) => '$returnUrl?sf_session_id=VSN1&sf_return_token=vsr_1');

      final back = await SecondFactor.verify(url: page, returnUrl: returnUrl);

      expect(back, const VerificationReturn('VSN1', 'vsr_1'));
      expect(calls.single.method, 'verify');
      expect(calls.single.arguments, {'url': page, 'host': 'app.example.com', 'path': '/verified'});
    });

    test('refuses a page that is not a verification page without opening it', () async {
      answer((_) => null);

      await expectLater(
        SecondFactor.verify(url: 'javascript:alert(1)//#vst_abc', returnUrl: returnUrl),
        failsWith(SecondFactorError.notAVerificationPage),
      );
      expect(calls, isEmpty);
    });

    for (final bad in ['myapp://verified', 'http://app.example.com/verified', 'https:///verified', 'not a url']) {
      test('refuses the return URL "$bad" without opening anything', () async {
        answer((_) => null);

        await expectLater(
          SecondFactor.verify(url: page, returnUrl: bad),
          failsWith(SecondFactorError.invalidReturnUrl),
        );
        expect(calls, isEmpty);
      });
    }

    test('turns a platform error it knows into a SecondFactorException', () async {
      answer((_) => throw PlatformException(code: 'canceled', message: 'closed'));

      await expectLater(SecondFactor.verify(url: page, returnUrl: returnUrl), failsWith(SecondFactorError.canceled));
    });

    test('passes any other platform error through unchanged', () async {
      answer((_) => throw PlatformException(code: 'somethingElse'));

      await expectLater(
        SecondFactor.verify(url: page, returnUrl: returnUrl),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'somethingElse')),
      );
    });

    test('fails when the return carries no session', () async {
      answer((_) => returnUrl);

      await expectLater(
        SecondFactor.verify(url: page, returnUrl: returnUrl),
        failsWith(SecondFactorError.missingReturnParameters),
      );
    });
  });
}
