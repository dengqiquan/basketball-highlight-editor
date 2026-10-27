import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final exportOutputPickerProvider = Provider((ref) => ExportOutputPicker());

/// Keeps the native modal boundary replaceable in export regression tests.
class ExportOutputPicker {
  Future<List<String>> videoPaths({required String typeLabel}) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: typeLabel,
          extensions: ['mp4', 'mov', 'm4v', 'avi', 'mkv'],
          mimeTypes: ['video/*'],
          uniformTypeIdentifiers: ['public.movie'],
        ),
      ],
    );
    return [for (final file in files) file.path];
  }

  Future<String?> mergedPath({required String typeLabel}) async {
    final location = await getSaveLocation(
      suggestedName: 'highlights.mp4',
      acceptedTypeGroups: [
        XTypeGroup(label: typeLabel, extensions: ['mp4']),
      ],
    );
    return location?.path;
  }

  Future<String?> directory({required String confirmLabel}) =>
      getDirectoryPath(confirmButtonText: confirmLabel);
}
