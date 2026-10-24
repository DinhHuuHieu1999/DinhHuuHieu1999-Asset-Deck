import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('synthetic baseline before inventory UI implementation', (
    tester,
  ) async {
    final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
    if (font != null) {
      final loader = FontLoader('Capture');
      loader.addFont(
        Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
      );
      await loader.load();
    }
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Capture'),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            appBar: AppBar(title: const Text('Asset Desk')),
            body: const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Synthetic baseline: inventory, search and manual equipment records. No backend connected.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../.local/flutter-ui/baseline.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  });
}
