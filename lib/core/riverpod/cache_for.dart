import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/campus/presentation/campus_providers.dart';

const defaultCacheDuration = Duration(minutes: 5);

extension CacheFor on Ref {
  /// Keeps this provider alive for [duration] after active listeners pause or
  /// detach, and drops the cache immediately when the user or campus changes.
  /// Returns null without keeping alive if the required user/campus scope is absent.
  KeepAliveLink? cacheFor(
    Duration duration, {
    bool userScoped = true,
    CampusScope? campusScope,
  }) {
    if (userScoped && read(currentUserIdProvider) == null) return null;
    if (campusScope != null && read(campusIdProvider(campusScope)) == null) {
      return null;
    }

    final link = keepAlive();
    Timer? timer;
    var disposed = false;

    void cancelTimer() {
      timer?.cancel();
      timer = null;
    }

    void dropCache() {
      cancelTimer();
      link.close();
    }

    onCancel(() {
      if (disposed) return;
      cancelTimer();
      timer = Timer(duration, link.close);
    });

    onResume(cancelTimer);

    onDispose(() {
      disposed = true;
      cancelTimer();
    });

    if (userScoped) {
      listen<String?>(currentUserIdProvider, (prev, next) {
        if (prev != next) dropCache();
      });
    }
    if (campusScope != null) {
      listen<String?>(campusIdProvider(campusScope), (prev, next) {
        if (prev != next) dropCache();
      });
    }

    return link;
  }
}
