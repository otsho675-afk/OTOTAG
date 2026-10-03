import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/core/theme/app_motion.dart';
import 'package:ototag/core/theme/app_theme.dart';

Widget host(Widget child, {bool reduced = false, bool accessible = false}) =>
    MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: MediaQueryData(
            disableAnimations: reduced, accessibleNavigation: accessible),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('entrance settles, caches content and does not replay on rebuild',
      (tester) async {
    var builds = 0;
    final content = Builder(builder: (_) {
      builds++;
      return const SizedBox(width: 120, height: 60, child: Text('İçerik'));
    });
    await tester.pumpWidget(host(AppEntrance(child: content)));
    final start = tester.getTopLeft(find.text('İçerik'));
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(find.text('İçerik'));
    expect(start.dy - end.dy, closeTo(8, .01));
    expect(builds, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(host(AppEntrance(child: content)));
    expect(tester.getTopLeft(find.text('İçerik')), end);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('press cancellation, tap and keyboard activation stay usable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(AppInteractiveSurface(
      onTap: () => taps++,
      child: const Padding(padding: EdgeInsets.all(24), child: Text('Hizmet')),
    )));
    final target = find.text('Hizmet');
    final press = await tester.startGesture(tester.getCenter(target));
    await tester.pumpAndSettle();
    await press.cancel();
    await tester.pumpAndSettle();
    expect(taps, 0);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 2);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('hover settles and disabled surfaces cannot activate',
      (tester) async {
    await tester.pumpWidget(host(const AppInteractiveSurface(
        onTap: null,
        child: SizedBox(width: 120, height: 60, child: Text('Pasif')))));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Pasif')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pasif'));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  for (final accessible in [false, true]) {
    testWidgets('reduced motion is immediate (accessible: $accessible)',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        AppEntrance(
          child: AppInteractiveSurface(
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 60, child: Text('Hazır')),
          ),
        ),
        reduced: !accessible,
        accessible: accessible,
      ));
      final position = tester.getTopLeft(find.text('Hazır'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.text('Hazır')), position);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.tap(find.text('Hazır'));
      expect(taps, 1);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('reduced motion skips route effects on $platform',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        theme: appTheme().copyWith(platform: platform),
        navigatorKey: navigator,
        builder: (_, child) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true), child: child!),
        home: const Scaffold(body: Text('Başlangıç')),
      ));
      navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
              body: Center(
                  child:
                      SizedBox(width: 100, height: 50, child: Text('Yeni'))))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final position = tester.getTopLeft(find.text('Yeni'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Yeni')), position);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Başlangıç'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
