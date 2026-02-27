import 'dart:io' show Platform;

/// Returns true when running on Android (non-web).
bool get isAndroidPlatform => Platform.isAndroid;
