// A minimal app around SecondFactor.verify. In a real app the page URL comes
// from your server's createSession call, and the return token goes back to
// your server, which passes it to verifySession.
import 'package:flutter/material.dart';
import 'package:secondfactor/secondfactor.dart';

void main() => runApp(const MaterialApp(home: VerifyScreen()));

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _pageUrl = TextEditingController();
  final _returnUrl = TextEditingController(
    text: 'https://app.example.com/verified',
  );
  String _status = 'Paste the url from createSession, then press Verify.';

  Future<void> _verify() async {
    setState(() => _status = 'Waiting for the user…');
    try {
      final back = await SecondFactor.verify(
        url: _pageUrl.text.trim(),
        returnUrl: _returnUrl.text.trim(),
      );
      setState(
        () => _status = back.returnToken == null
            ? 'Returned without verifying (session ${back.sessionId}).'
            : 'Verified. Send the return token to your server for session ${back.sessionId}.',
      );
    } on SecondFactorException catch (e) {
      setState(() => _status = 'Not verified: ${e.error.name}. ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('secondfactor.ai')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _pageUrl,
          decoration: const InputDecoration(labelText: 'Page url (#vst_…)'),
        ),
        TextField(
          controller: _returnUrl,
          decoration: const InputDecoration(labelText: 'Return url'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _verify, child: const Text('Verify')),
        const SizedBox(height: 16),
        Text(_status),
      ],
    ),
  );
}
