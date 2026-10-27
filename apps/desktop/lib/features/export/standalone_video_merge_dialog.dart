import 'dart:async';
import 'dart:io';

import 'package:bhe_l10n/bhe_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine_session.dart';
import '../../providers/export_output_picker.dart';
import '../../providers/playback_coordinator.dart';
import '../../providers/session_provider.dart';

final videoMergeGatewayProvider = Provider<VideoMergeGateway>(
  (ref) =>
      EngineVideoMergeGateway(EngineSession(ref.read(engineClientProvider))),
);

abstract class VideoMergeGateway {
  Future<Map<String, dynamic>> start(List<String> paths, String outputPath);
  Future<Map<String, dynamic>> status(String jobId);
  Future<void> cancel(String jobId);
}

class EngineVideoMergeGateway implements VideoMergeGateway {
  EngineVideoMergeGateway(this.engine);
  final EngineSession engine;

  @override
  Future<Map<String, dynamic>> start(List<String> paths, String outputPath) =>
      engine.startVideoMerge(inputPaths: paths, outputPath: outputPath);

  @override
  Future<Map<String, dynamic>> status(String jobId) =>
      engine.getVideoMerge(jobId);

  @override
  Future<void> cancel(String jobId) async {
    await engine.cancelVideoMerge(jobId);
  }
}

class StandaloneVideoMergeDialog extends ConsumerStatefulWidget {
  const StandaloneVideoMergeDialog({super.key});

  @override
  ConsumerState<StandaloneVideoMergeDialog> createState() =>
      _StandaloneVideoMergeDialogState();
}

class _StandaloneVideoMergeDialogState
    extends ConsumerState<StandaloneVideoMergeDialog> {
  final List<String> _paths = [];
  bool _choosing = false;
  String? _jobId;
  String? _state;
  String? _output;
  String? _error;
  double _progress = 0;

  bool get _running =>
      _state == 'queued' || _state == 'running' || _state == 'cancelling';

  Future<T> _withPausedPlayback<T>(Future<T> Function() action) =>
      ref.read(playbackCoordinatorProvider).withPausedPlayback(action);

  Future<void> _addVideos() async {
    if (_choosing || _running) return;
    setState(() => _choosing = true);
    try {
      final selected = await _withPausedPlayback(() async {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return <String>[];
        return ref
            .read(exportOutputPickerProvider)
            .videoPaths(typeLabel: context.bheText('视频'));
      });
      if (!mounted) return;
      setState(() {
        for (final path in selected) {
          if (!_paths.contains(path)) _paths.add(path);
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  void _move(int index, int offset) {
    setState(() {
      final path = _paths.removeAt(index);
      _paths.insert(index + offset, path);
    });
  }

  Future<void> _start() async {
    if (_paths.length < 2 || _choosing || _running) return;
    setState(() {
      _choosing = true;
      _error = null;
      _output = null;
    });
    try {
      final output = await _withPausedPlayback(() async {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return null;
        return ref
            .read(exportOutputPickerProvider)
            .mergedPath(typeLabel: context.bheText('视频'));
      });
      if (!mounted || output == null) return;
      final response = await ref
          .read(videoMergeGatewayProvider)
          .start(List.of(_paths), output);
      if (!mounted) return;
      final job = (response['job'] as Map).cast<String, dynamic>();
      setState(() {
        _jobId = job['id']?.toString();
        _state = job['state']?.toString();
        _progress = 0;
      });
      unawaited(_poll());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _poll() async {
    final id = _jobId;
    if (id == null) return;
    while (mounted && _jobId == id && _running) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted || _jobId != id) return;
      try {
        final response = await ref.read(videoMergeGatewayProvider).status(id);
        if (!mounted || _jobId != id) return;
        final job = (response['job'] as Map).cast<String, dynamic>();
        setState(() {
          _state = job['state']?.toString();
          _progress = (job['progress'] as num?)?.toDouble() ?? 0;
          _output = job['output_path']?.toString();
          _error = _state == 'failed' ? job['error_message']?.toString() : null;
        });
      } catch (error) {
        if (mounted) {
          setState(() {
            _state = 'failed';
            _error = error.toString();
          });
        }
      }
    }
  }

  Future<void> _cancel() async {
    final id = _jobId;
    if (id == null) return;
    try {
      await ref.read(videoMergeGatewayProvider).cancel(id);
      if (mounted) setState(() => _state = 'cancelling');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _openOutputFolder() async {
    final path = _output;
    if (path == null) return;
    final folder = File(path).parent.path;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [folder]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [folder]);
      } else {
        await Process.start('xdg-open', [folder]);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running && !_choosing,
    child: AlertDialog(
      title: Text(context.bheText('合并已有视频')),
      content: SizedBox(
        width: 570,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.bheText('选择至少两个本地视频，按下方顺序合并为一个 MP4。')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _choosing || _running ? null : _addVideos,
              icon: const Icon(Icons.add),
              label: Text(context.bheText('添加视频')),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _paths.isEmpty
                  ? Center(child: Text(context.bheText('尚未选择视频')))
                  : ListView.builder(
                      itemCount: _paths.length,
                      itemBuilder: (context, index) => ListTile(
                        key: Key('merge-video-$index'),
                        dense: true,
                        leading: Text('${index + 1}'),
                        title: Text(
                          File(_paths[index]).uri.pathSegments.last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _paths[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: context.bheText('上移'),
                              onPressed: index == 0 || _running
                                  ? null
                                  : () => _move(index, -1),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: context.bheText('下移'),
                              onPressed: index == _paths.length - 1 || _running
                                  ? null
                                  : () => _move(index, 1),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              tooltip: context.bheText('移除'),
                              onPressed: _running
                                  ? null
                                  : () =>
                                        setState(() => _paths.removeAt(index)),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (_running) ...[
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 8),
              Text(
                context.bheText(_state == 'cancelling' ? '正在取消…' : '正在合并视频…'),
              ),
            ],
            if (_state == 'completed') ...[
              Text(context.bheText('合并完成：$_output')),
              TextButton(
                onPressed: _openOutputFolder,
                child: Text(context.bheText('打开目录')),
              ),
            ],
            if (_state == 'cancelled') Text(context.bheText('合并已取消')),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        if (_running)
          TextButton(
            onPressed: _state == 'cancelling' ? null : _cancel,
            child: Text(context.bheText('取消任务')),
          ),
        TextButton(
          onPressed: _running || _choosing
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(context.bheText('关闭')),
        ),
        FilledButton(
          key: const Key('standalone-merge-start'),
          onPressed: _paths.length >= 2 && !_choosing && !_running
              ? _start
              : null,
          child: Text(context.bheText('合并导出')),
        ),
      ],
    ),
  );
}
