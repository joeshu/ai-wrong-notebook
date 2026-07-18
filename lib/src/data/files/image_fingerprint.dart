import 'dart:io';
import 'package:crypto/crypto.dart';

/// Keeps a SHA-256 fingerprint in the existing durable tag column. The hash
/// never leaves the device; it lets later analysis reuse an exact local image
/// result without another model request.
class ImageFingerprintCodec {
  const ImageFingerprintCodec._();

  static const _prefix = '__system_image_sha256:';

  static String? read(Iterable<String> tags) {
    for (final tag in tags) {
      if (tag.startsWith(_prefix)) return tag.substring(_prefix.length);
    }
    return null;
  }

  static List<String> write(Iterable<String> tags, String fingerprint) {
    final result = tags.where((tag) => !tag.startsWith(_prefix)).toList();
    if (fingerprint.isNotEmpty) result.add('$_prefix$fingerprint');
    return result;
  }

  static Future<String> fromFile(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();
}
