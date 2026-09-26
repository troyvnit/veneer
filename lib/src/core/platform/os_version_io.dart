import 'dart:io' show Platform;

/// The running iOS major version, or null elsewhere.
/// `Platform.operatingSystemVersion` on iOS reads like "Version 26.0 (Build 23A…)".
int? iosMajorVersion() {
  if (!Platform.isIOS) return null;
  final match = RegExp(r'(\d+)\.').firstMatch(Platform.operatingSystemVersion);
  return match == null ? null : int.tryParse(match.group(1)!);
}
