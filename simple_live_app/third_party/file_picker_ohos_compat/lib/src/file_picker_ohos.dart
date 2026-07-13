import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// HarmonyOS implementation backed by OpenHarmony-SIG file_selector.
class FilePickerOhos extends FilePicker {
  static void registerWith() {
    FilePicker.platform = FilePickerOhos();
  }

  List<selector.XTypeGroup> _typeGroups(
    FileType type,
    List<String>? extensions,
  ) {
    if (type == FileType.any || (extensions?.isEmpty ?? true)) {
      return const <selector.XTypeGroup>[];
    }
    return <selector.XTypeGroup>[
      selector.XTypeGroup(
        label: type.name,
        extensions: extensions,
      ),
    ];
  }

  Future<PlatformFile> _toPlatformFile(
    selector.XFile file, {
    required bool withData,
    required bool withReadStream,
  }) async {
    final bytes = withData ? await file.readAsBytes() : null;
    final size = await file.length();
    return PlatformFile(
      name: file.name,
      path: file.path,
      size: size,
      bytes: bytes,
      readStream: withReadStream ? file.openRead() : null,
    );
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    onFileLoading?.call(FilePickerStatus.picking);
    final groups = _typeGroups(type, allowedExtensions);
    final files = allowMultiple
        ? await selector.openFiles(
            acceptedTypeGroups: groups,
            initialDirectory: initialDirectory,
          )
        : <selector.XFile>[
            if (await selector.openFile(
              acceptedTypeGroups: groups,
              initialDirectory: initialDirectory,
            )
                case final selected?)
              selected,
          ];
    onFileLoading?.call(FilePickerStatus.done);
    if (files.isEmpty) {
      return null;
    }
    final converted = <PlatformFile>[];
    for (final file in files) {
      converted.add(
        await _toPlatformFile(
          file,
          withData: withData,
          withReadStream: withReadStream,
        ),
      );
    }
    return FilePickerResult(converted);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) {
    return selector.getDirectoryPath(initialDirectory: initialDirectory);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    if (bytes == null) {
      return null;
    }
    final directory = await getApplicationDocumentsDirectory();
    final target = File(path.join(directory.path, fileName ?? 'export.dat'));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  @override
  Future<bool?> clearTemporaryFiles() async => true;
}
