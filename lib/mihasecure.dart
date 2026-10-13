import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum MihaSecureStatus { checking, verified, denied }

/// Whether the authentic MihaSecure app is installed: the right package,
/// signed with MihaSecure's certificate. The check itself is local and runs
/// on the Android side (MihaSecure in MainActivity.kt); anything but a
/// confirmed match, including an error, denies access.
class MihaSecureAccess extends ValueNotifier<MihaSecureStatus> {
  MihaSecureAccess() : super(MihaSecureStatus.checking);

  static const channel = MethodChannel('com.miha.translate/mihasecure');

  /// The check is local and quick; one that never answers counts as failed,
  /// so the app cannot stay on the progress screen.
  static const timeout = Duration(seconds: 10);

  Future<bool>? _running;

  /// Checks again and returns whether access is granted.
  ///
  /// Until a check finishes, an earlier "verified" stays as it is, so coming
  /// back to the app does not flash a progress screen; otherwise the status
  /// is "checking" meanwhile. Calls during a check share its result.
  Future<bool> check() {
    if (value != MihaSecureStatus.verified) value = MihaSecureStatus.checking;
    return _running ??= _verify().whenComplete(() => _running = null);
  }

  Future<bool> _verify() async {
    var verified = false;
    try {
      verified = await channel.invokeMethod<String>('verify').timeout(timeout) == 'verified';
    } catch (_) {
      verified = false;
    }
    value = verified ? MihaSecureStatus.verified : MihaSecureStatus.denied;
    return verified;
  }
}

final mihaSecure = MihaSecureAccess();
