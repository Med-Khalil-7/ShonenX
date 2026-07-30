import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceInfo {
  DeviceInfo._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static AndroidDeviceInfo? _cachedInfo;

  static Future<AndroidDeviceInfo> _info() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('This device is not Android');
    }

    return _cachedInfo ??= await _deviceInfo.androidInfo;
  }

  static Future<bool> isAndroid10OrBelow() async {
    final info = await _info();
    return info.version.sdkInt <= 29;
  }

  static Future<bool> isAndroid11OrAbove() async {
    final info = await _info();
    return info.version.sdkInt >= 30;
  }

  /// True when running on Android TV / Google TV.
  ///
  /// `android.software.leanback` is declared by every Android TV device and by
  /// essentially no phone, so it is the primary signal. The television
  /// hardware feature corroborates it for set-top boxes.
  static Future<bool> isTelevision() async {
    if (!Platform.isAndroid) return false;
    try {
      final features = (await _info()).systemFeatures;
      return features.contains('android.software.leanback') ||
          features.contains('android.software.leanback_only') ||
          features.contains('android.hardware.type.television');
    } catch (_) {
      return false;
    }
  }
}
