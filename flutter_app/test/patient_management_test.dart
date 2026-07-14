import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart';

void main() {
  testWidgets('Patient list shows seeded patients and allows adding one',
      (WidgetTester tester) async {
    await tester.pumpWidget(const RehabGloveApp());
    await tester.pumpAndSettle();

    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Noa Levi'), findsOneWidget);
    expect(find.text('David Cohen'), findsOneWidget);

    // Adding a patient with an empty name should be blocked by validation.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Add Patient'), findsNWidgets(2)); // AppBar title + submit button

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Patient'));
    await tester.pumpAndSettle();
    expect(find.text('Name is required'), findsOneWidget);
    // Still on the form screen since validation blocked submission.
    expect(find.byType(TextFormField), findsNWidgets(3));

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Test Patient');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Patient'));
    await tester.pumpAndSettle();

    // Back on the list, the new patient should appear.
    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Test Patient'), findsOneWidget);
  });

  testWidgets('Patient detail shows prescriptions and editing updates them',
      (WidgetTester tester) async {
    await tester.pumpWidget(const RehabGloveApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Noa Levi'));
    await tester.pumpAndSettle();

    // Top-of-list cards are built immediately.
    expect(find.text('Cubes & Boxes'), findsOneWidget);
    expect(find.text('Pinch Grip'), findsOneWidget);
    expect(find.textContaining('Cycles: 3'), findsOneWidget);

    // Set active patient (button is in the header banner, on screen).
    await tester.tap(find.widgetWithText(ElevatedButton, 'Set Active Patient'));
    await tester.pumpAndSettle();
    expect(find.text('Active Patient'), findsOneWidget);

    // Edit the cubesBoxes prescription (the whole card is tappable).
    final cubesBoxesCard = find.ancestor(
      of: find.text('Cubes & Boxes'),
      matching: find.byType(InkWell),
    );
    await tester.tap(cubesBoxesCard);
    await tester.pumpAndSettle();

    expect(find.text('Edit Cubes & Boxes Prescription'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Cycles'), '5');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cycles: 5'), findsOneWidget);

    // The third card builds once scrolled into view.
    await tester.scrollUntilVisible(find.text('Finger Bend'), 200);
    expect(find.text('Finger Bend'), findsOneWidget);
  });

  testWidgets('Telemetry dashboard is still reachable', (WidgetTester tester) async {
    await tester.pumpWidget(const RehabGloveApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sensors));
    await tester.pumpAndSettle();

    expect(find.text('REHAB GLOVE HUB'), findsOneWidget);
  });

  testWidgets('Calibration tools menu lists FSR and Box options', (WidgetTester tester) async {
    await tester.pumpWidget(const RehabGloveApp());
    await tester.pumpAndSettle();

    // Open the calibration tools popup menu (navigating into the screens
    // themselves starts live polling timers, so we only verify the menu here).
    await tester.tap(find.byIcon(Icons.build_rounded));
    await tester.pumpAndSettle();
    expect(find.text('FSR calibration'), findsOneWidget);
    expect(find.text('Box calibration'), findsOneWidget);
  });

  testWidgets('Analytics screen renders progress charts', (WidgetTester tester) async {
    await tester.pumpWidget(const RehabGloveApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Noa Levi'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'View progress & analytics'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Progress ·'), findsOneWidget);
    expect(find.text('Success rate'), findsOneWidget);
    // Later charts build once scrolled into view.
    await tester.scrollUntilVisible(find.text('Grip force'), 200);
    expect(find.text('Grip force'), findsOneWidget);
  });
}
