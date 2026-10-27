import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/floating_nav.dart';

/// Test độc lập cho FloatingNav — không cần dữ liệu/API.
void main() {
  const List<NavItem> items = <NavItem>[
    NavItem(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      label: 'Khám phá',
    ),
    NavItem(
      icon: Icons.library_books_outlined,
      selectedIcon: Icons.library_books,
      label: 'Tủ sách',
    ),
    NavItem(
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note,
      label: 'Đăng truyện',
    ),
    NavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Tài khoản',
    ),
  ];

  const List<String> labels = <String>[
    'Khám phá',
    'Tủ sách',
    'Đăng truyện',
    'Tài khoản',
  ];

  /// App giả có thanh nav; `index` đổi bằng tay để kiểm tra trạng thái.
  Widget harness({
    required ValueNotifier<int> index,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) {
    return MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      // Ép cỡ chữ qua builder để kiểm tra nhãn không tràn khi hệ thống to.
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: const SizedBox.shrink(),
        // Nghe ValueNotifier để nav rebuild khi đổi tab trong test.
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (BuildContext context, int value, _) => FloatingNav(
            items: items,
            currentIndex: value,
            onChanged: (int i) => index.value = i,
          ),
        ),
      ),
    );
  }

  testWidgets('đúng4 mục, mỗi mục luôn có icon + nhãn', (tester) async {
    final ValueNotifier<int> index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await tester.pumpWidget(harness(index: index));
    await tester.pumpAndSettle();

    for (int i = 0; i < 4; i++) {
      expect(
        find.byKey(ValueKey<int>(i)),
        findsOneWidget,
        reason: 'thiếu mục $i',
      );
    }
    for (final String label in labels) {
      expect(
        find.descendant(
          of: find.byType(FloatingNav),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'mục "$label" phải LUÔN có nhãn',
      );
    }
    // Mỗi mục đúng 1 icon (outline hoặc filled tùy trạng thái)
    final Finder navIcons = find.descendant(
      of: find.byType(FloatingNav),
      matching: find.byIcon(Icons.explore),
    );
    expect(navIcons, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FloatingNav),
        matching: find.byIcon(Icons.explore_outlined),
      ),
      findsNothing,
    ); // tab0 đang chọn → icon filled
  });

  testWidgets('kích thước thanh và từng mục KHÔNG đổi khi chuyển tab', (
    tester,
  ) async {
    final ValueNotifier<int> index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await tester.pumpWidget(harness(index: index));
    await tester.pumpAndSettle();

    final Size bar = tester.getSize(find.byType(FloatingNav));
    final List<Size> itemSizes = <Size>[
      for (int i = 0; i < 4; i++) tester.getSize(find.byKey(ValueKey<int>(i))),
    ];
    // 4 mục chia đều
    expect(itemSizes[0].width, moreOrLessEquals(itemSizes[1].width));
    expect(itemSizes[0].height, moreOrLessEquals(itemSizes[1].height));

    for (int tab = 1; tab < 4; tab++) {
      index.value = tab;
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(FloatingNav)),
        bar,
        reason: 'thanh đổi size',
      );
      for (int i = 0; i < 4; i++) {
        expect(
          tester.getSize(find.byKey(ValueKey<int>(i))),
          itemSizes[i],
          reason: 'mục $i đổi size khi đang ở tab $tab',
        );
      }
    }
  });

  testWidgets('Semantics: button + selected đúng mục đang chọn', (
    tester,
  ) async {
    final ValueNotifier<int> index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await tester.pumpWidget(harness(index: index));
    await tester.pumpAndSettle();

    final SemanticsHandle handle = tester.ensureSemantics();

    // Mục đang chọn
    final SemanticsNode selected = tester.getSemantics(find.text('Khám phá'));
    expect(selected.label, 'Khám phá');
    expect(selected.flagsCollection.isButton, isTrue);
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    // Mục chưa chọn
    final SemanticsNode other = tester.getSemantics(find.text('Tài khoản'));
    expect(other.flagsCollection.isSelected, isNot(Tristate.isTrue));

    // Chạm vào mục Tài khoản → selected đổi theo
    await tester.tap(find.byKey(const ValueKey<int>(3)));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Tài khoản')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    handle.dispose();
  });

  testWidgets('sáng/tối và cỡ chữ hệ thống lớn không tràn nhãn', (
    tester,
  ) async {
    for (final Brightness brightness in <Brightness>[
      Brightness.light,
      Brightness.dark,
    ]) {
      for (final double scale in <double>[1.0, 2.0]) {
        final ValueNotifier<int> index = ValueNotifier<int>(0);
        await tester.pumpWidget(
          harness(index: index, brightness: brightness, textScale: scale),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow $brightness x$scale',
        );
        // Nhãn vẫn1 dòng, nằm trọn trong mục
        for (int i = 0; i < 4; i++) {
          final Finder labelFinder = find.descendant(
            of: find.byKey(ValueKey<int>(i)),
            matching: find.text(labels[i]),
          );
          expect(labelFinder, findsOneWidget);
          final Rect label = tester.getRect(labelFinder);
          final Rect item = tester.getRect(find.byKey(ValueKey<int>(i)));
          expect(
            item.contains(label.center),
            isTrue,
            reason: 'nhãn "${labels[i]}" tràn khỏi mục ($brightness x$scale)',
          );
          expect(label.width, lessThanOrEqualTo(item.width));
        }
        index.dispose();
      }
    }
  });
}
