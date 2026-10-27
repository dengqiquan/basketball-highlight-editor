import 'dart:async';

import 'package:desktop/features/export/standalone_video_merge_dialog.dart';
import 'package:desktop/providers/export_output_picker.dart';
import 'package:desktop/providers/playback_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('merge uses the displayed order and selected output', (
    tester,
  ) async {
    final picker = _Picker();
    final gateway = _Gateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exportOutputPickerProvider.overrideWithValue(picker),
          videoMergeGatewayProvider.overrideWithValue(gateway),
          playbackCoordinatorProvider.overrideWithValue(PlaybackCoordinator()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StandaloneVideoMergeDialog()),
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('standalone-merge-start')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('添加视频'));
    await tester.pumpAndSettle();
    expect(find.text('first.mp4'), findsOneWidget);
    expect(find.text('second.mp4'), findsOneWidget);
    await tester.tap(find.byTooltip('上移').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('standalone-merge-start')));
    await tester.pumpAndSettle();
    expect(gateway.paths, ['/tmp/second.mp4', '/tmp/first.mp4']);
    expect(gateway.output, '/tmp/joined.mp4');
  });

  testWidgets('cancelled save dialog does not start a merge', (tester) async {
    final picker = _Picker()..output = null;
    final gateway = _Gateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exportOutputPickerProvider.overrideWithValue(picker),
          videoMergeGatewayProvider.overrideWithValue(gateway),
          playbackCoordinatorProvider.overrideWithValue(PlaybackCoordinator()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StandaloneVideoMergeDialog()),
        ),
      ),
    );
    await tester.tap(find.text('添加视频'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('standalone-merge-start')));
    await tester.pumpAndSettle();
    expect(gateway.paths, isEmpty);
  });

  testWidgets('dialog cannot close while engine is accepting a merge', (
    tester,
  ) async {
    final picker = _Picker();
    final gateway = _SlowGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exportOutputPickerProvider.overrideWithValue(picker),
          videoMergeGatewayProvider.overrideWithValue(gateway),
          playbackCoordinatorProvider.overrideWithValue(PlaybackCoordinator()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StandaloneVideoMergeDialog()),
        ),
      ),
    );
    await tester.tap(find.text('添加视频'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('standalone-merge-start')));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '关闭'))
          .onPressed,
      isNull,
    );
    gateway.accept.complete({
      'job': {'id': 'job', 'state': 'completed'},
    });
    await tester.pumpAndSettle();
  });
}

class _SlowGateway extends _Gateway {
  final accept = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> start(List<String> paths, String outputPath) =>
      accept.future;
}

class _Picker extends ExportOutputPicker {
  String? output = '/tmp/joined.mp4';
  @override
  Future<List<String>> videoPaths({required String typeLabel}) async => [
    '/tmp/first.mp4',
    '/tmp/second.mp4',
  ];
  @override
  Future<String?> mergedPath({required String typeLabel}) async => output;
}

class _Gateway implements VideoMergeGateway {
  List<String> paths = [];
  String? output;
  @override
  Future<Map<String, dynamic>> start(
    List<String> paths,
    String outputPath,
  ) async {
    this.paths = paths;
    output = outputPath;
    return {
      'job': {'id': 'job', 'state': 'completed'},
    };
  }

  @override
  Future<Map<String, dynamic>> status(String jobId) async => {
    'job': {'id': jobId, 'state': 'completed'},
  };
  @override
  Future<void> cancel(String jobId) async {}
}
