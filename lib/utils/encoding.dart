import 'dart:convert';
import 'dart:typed_data';

/// Converts a Uint8List to a Base64 string.
String uint8ArrayToBase64(Uint8List bytes) {
  return base64.encode(bytes);
}

/// Converts a Base64 string to a Uint8List.
Uint8List base64ToUint8Array(String base64String) {
  return base64.decode(base64String);
}

/// Helper to encode string to bytes (UTF-8)
Uint8List stringToBytes(String text) {
  return Uint8List.fromList(utf8.encode(text));
}

/// Helper to decode bytes to string (UTF-8)
String bytesToString(Uint8List bytes) {
  return utf8.decode(bytes);
}
