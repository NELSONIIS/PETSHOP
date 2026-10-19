import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'repositories.dart';

/// Photo/document selection behind an interface so screens can be tested without platform channels.
abstract class MediaPicker {
  Future<List<UploadFile>> pickImages({bool camera = false, int limit = 8});
  Future<UploadFile?> pickDocument();
}

String _mimeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.pdf')) return 'application/pdf';
  return 'image/jpeg';
}

class DeviceMediaPicker implements MediaPicker {
  final _picker = ImagePicker();

  @override
  Future<List<UploadFile>> pickImages({bool camera = false, int limit = 8}) async {
    final files = camera
        ? [?await _picker.pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 88)]
        : await _picker.pickMultiImage(maxWidth: 2400, imageQuality: 88, limit: limit < 2 ? 2 : limit);
    final out = <UploadFile>[];
    for (final f in files) {
      final size = await File(f.path).length();
      out.add(UploadFile(name: f.name, mime: f.mimeType ?? _mimeFor(f.name), path: f.path, size: size));
    }
    return out;
  }

  @override
  Future<UploadFile?> pickDocument() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: false,
    );
    final f = r?.files.single;
    if (f == null || f.path == null) return null;
    return UploadFile(name: f.name, mime: _mimeFor(f.name), path: f.path, size: f.size);
  }
}

final mediaPickerProvider = Provider<MediaPicker>((ref) => DeviceMediaPicker());
