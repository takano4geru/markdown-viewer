// This is a basic Flutter widget test for the CloudSync Docs app.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:google_drive_app/main.dart';
import 'package:google_drive_app/providers/auth_provider.dart';

class FakeAuthNotifier extends AuthNotifier {
  @override
  Future<void> silentSignIn() async {
    // Override to prevent real Google Sign-In call in unit tests
  }
}

void main() {
  testWidgets('App smoke test - Login screen is shown', (WidgetTester tester) async {
    // Build our app wrapped in ProviderScope with overridden authProvider and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => FakeAuthNotifier()),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pump();

    // Verify that our app shows the login screen title and sign-in button
    expect(find.text('CloudSync Docs'), findsOneWidget);
    expect(find.text('Sign In with Google'), findsOneWidget);
  });
}
