// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wish_wallet/main.dart';

Future<String> _saveRecoveryCode(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final code = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
  await tester.tap(find.text("I've saved it"));
  await tester.pumpAndSettle();
  return code;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the WishWallet sign-in screen', (tester) async {
    await tester.pumpWidget(const WishWalletApp());
    await tester.pumpAndSettle();

    expect(find.text('WishWallet'), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
    expect(find.text('Wish it. Want it. Win it.'), findsOneWidget);
  });

  testWidgets('creates multiple separate offline accounts', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WishWalletApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don’t have an account?  Create it'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Agalya');
    expect(find.text('PHONE NUMBER'), findsNothing);
    await tester.enterText(find.byType(TextField).at(1), 'Wish1234');
    await tester.enterText(find.byType(TextField).at(2), 'Wish1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create it'));
    await tester.pumpAndSettle();
    await _saveRecoveryCode(tester);
    expect(find.text('My Wishes!!!  ♥'), findsOneWidget);
    expect(find.text('Sarees'), findsNothing);
    expect(find.text('Shirts'), findsNothing);
    expect(find.text('Shoe'), findsNothing);
    expect(find.text('Accessories'), findsNothing);
    expect(find.byTooltip('Add a new wish'), findsNothing);

    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Wish it. Want it. Win it.'), findsOneWidget);
    expect(find.text('PHONE NUMBER'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don’t have an account?  Create it'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'SecondUser');
    await tester.enterText(find.byType(TextField).at(1), 'Other1234');
    await tester.enterText(find.byType(TextField).at(2), 'Other1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create it'));
    await tester.pumpAndSettle();
    await _saveRecoveryCode(tester);

    expect(find.text('My Wishes!!!  ♥'), findsOneWidget);
    expect(find.text('White Floral Kurti'), findsNothing);
    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    expect(find.text('PHONE NUMBER'), findsNothing);
  });

  testWidgets('demo account keeps categories when signed out and back in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WishWalletApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with demo account'));
    await tester.pumpAndSettle();

    expect(find.text('Red Checkered Saree'), findsOneWidget);
    await tester.tap(find.text('＋ Add a new wish'));
    await tester.pumpAndSettle();
    expect(find.text('Fetch name and price from link'), findsOneWidget);
    expect(find.text('PRICE (OPTIONAL)'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '♥  Save My Wish'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://example.com/saree',
    );
    await tester.tap(find.text('Fetch name and price from link'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Automatic lookup is unavailable:'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(0), 'Manual Saree');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '♥  Save My Wish'));
    await tester.pumpAndSettle();
    expect(find.text('Manual Saree'), findsOneWidget);

    await tester.tap(find.text('＋ Create a category'));
    await tester.pumpAndSettle();
    final categoryTitle = tester.widget<Text>(
      find.text('Wow! Creating a new Category'),
    );
    expect(categoryTitle.maxLines, 1);
    expect(find.text('Group similar wishes together.'), findsOneWidget);
    expect(find.text('like Sarees or Shoes.'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), 'Demo Picks');
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final createCategoryButton = find.widgetWithText(
      ElevatedButton,
      '+  Create my Category',
    );
    await tester.ensureVisible(createCategoryButton);
    await tester.pumpAndSettle();
    await tester.tap(createCategoryButton);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('Demo Picks'), findsOneWidget);
    expect(find.text('Add a wish'), findsNothing);

    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with demo account'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(find.text('Demo Picks'), findsOneWidget);
  });

  testWidgets('offline recovery code resets password and rotates once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WishWalletApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don’t have an account?  Create it'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'PasswordUser');
    await tester.enterText(find.byType(TextField).at(1), 'Oldpass123');
    await tester.enterText(find.byType(TextField).at(2), 'Oldpass123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create it'));
    await tester.pumpAndSettle();
    final oldRecoveryCode = await _saveRecoveryCode(tester);
    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?  →'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'PasswordUser');
    await tester.enterText(find.byType(TextField).at(1), oldRecoveryCode);
    await tester.enterText(find.byType(TextField).at(2), 'Newpass456');
    await tester.enterText(find.byType(TextField).at(3), 'Newpass456');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
    await tester.pumpAndSettle();
    final newRecoveryCode = await _saveRecoveryCode(tester);
    expect(newRecoveryCode, isNot(oldRecoveryCode));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('My Wishes!!!  ♥'), findsOneWidget);
    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?  →'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'PasswordUser');
    await tester.enterText(find.byType(TextField).at(1), oldRecoveryCode);
    await tester.enterText(find.byType(TextField).at(2), 'Another789');
    await tester.enterText(find.byType(TextField).at(3), 'Another789');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
    await tester.pumpAndSettle();
    expect(find.text('RECOVERY CODE'), findsOneWidget);
    expect(find.text('Save your recovery code'), findsNothing);
  });

  testWidgets('profile deletes the account after confirmation', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WishWalletApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don’t have an account?  Create it'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'DeleteUser');
    await tester.enterText(find.byType(TextField).at(1), 'Delete123');
    await tester.enterText(find.byType(TextField).at(2), 'Delete123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create it'));
    await tester.pumpAndSettle();
    await _saveRecoveryCode(tester);
    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Delete account'), findsOneWidget);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('profile edits username and keeps account data', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WishWalletApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don’t have an account?  Create it'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'BeforeEdit');
    await tester.enterText(find.byType(TextField).at(1), 'Editpass123');
    await tester.enterText(find.byType(TextField).at(2), 'Editpass123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create it'));
    await tester.pumpAndSettle();
    await _saveRecoveryCode(tester);

    await tester.tap(find.text('＋ Create a category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Saved list');
    final createCategoryButton = find.widgetWithText(
      ElevatedButton,
      '+  Create my Category',
    );
    await tester.ensureVisible(createCategoryButton);
    await tester.pumpAndSettle();
    await tester.tap(createCategoryButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    expect(find.text('My Profile'), findsNWidgets(2));
    final profileTitle = tester.widget<Text>(find.text('My Profile').first);
    expect(profileTitle.maxLines, 1);
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'AfterEdit');
    await tester.enterText(find.byType(TextField).at(1), 'Editpass123');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('AfterEdit'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'AfterEdit');
    await tester.enterText(find.byType(TextField).at(1), 'Editpass123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    expect(find.text('AfterEdit'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
