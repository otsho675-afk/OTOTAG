import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/widgets/matching_status_card.dart';

void main() {
  final preview = GlobalKey();
  Widget host(
          {int stage = 0,
          bool reduced = false,
          bool ticker = true,
          bool active = true}) =>
      RepaintBoundary(
          key: preview,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(),
              home: MediaQuery(
                  data: MediaQueryData(
                      disableAnimations: reduced,
                      textScaler: const TextScaler.linear(1.4)),
                  child: Scaffold(
                      body: TickerMode(
                          enabled: ticker,
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: MatchingStatusCard(
                                  title: stage == 0
                                      ? 'Usta teklifleri bekleniyor'
                                      : '1 teklif geldi',
                                  message:
                                      'Talebiniz açık. Gelen teklifleri burada karşılaştırabilir, uygun ustayı seçebilirsiniz.',
                                  icon: Icons.radar_rounded,
                                  searching: true,
                                  stage: stage,
                                  active: active)))))));

  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  testWidgets(
      'search fits narrow screens and stops on offers, errors and reduced motion',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          preview.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/release-audit').create(recursive: true);
      await File('build/release-audit/matching-search-320.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    for (final widget in [
      host(stage: 1),
      host(active: false),
      host(reduced: true),
      host(ticker: false)
    ]) {
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search animation pauses in background and is disposed cleanly',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
