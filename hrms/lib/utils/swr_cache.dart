// hrms/lib/utils/swr_cache.dart
//
// Tiny in-memory "stale-while-revalidate" cache for screen data.
//
// Why: most screens fetch their data in initState and show a full-screen
// loader until the network round-trip finishes. Re-opening the same screen
// (e.g. from the drawer) repeats that loader every time, which reads as
// "screen-to-screen lag". With this cache a screen can paint the previously
// loaded data instantly, then silently refresh in the background.
//
// Semantics: a screen paints the cached value instantly, then decides whether
// to revalidate based on [isFresh]. Within the freshness window it skips the
// network entirely — so quickly moving tab-to-tab does NOT re-fetch or replay
// entry animations (no visible "double load"). Once the window passes, the
// screen refreshes silently in the background. The cache lives for the app
// session and is wiped on logout (see clearStoredAuthSession in
// core/network/dio_client.dart) so one user's data can never leak into another.
class SwrCache {
  SwrCache._();

  /// Default freshness window: skip revalidation if data is younger than this.
  /// Long enough that normal navigation never re-fetches, short enough that
  /// data refreshes within a reasonable time.
  static const Duration defaultTtl = Duration(minutes: 2);

  static final Map<String, Object?> _store = <String, Object?>{};
  static final Map<String, DateTime> _stamps = <String, DateTime>{};

  /// Last cached value for [key], or null if nothing is cached yet.
  static T? get<T>(String key) {
    final value = _store[key];
    return value is T ? value : null;
  }

  /// Stores [value] under [key] and stamps it as fresh as of now.
  static void set(String key, Object? value) {
    _store[key] = value;
    _stamps[key] = DateTime.now();
  }

  /// True when [key] was last [set] within [ttl] — i.e. fresh enough to skip a
  /// background refresh. False when missing or older than [ttl].
  static bool isFresh(String key, [Duration ttl = defaultTtl]) {
    final stamp = _stamps[key];
    if (stamp == null) return false;
    return DateTime.now().difference(stamp) < ttl;
  }

  /// Drops a single entry (e.g. after a mutation that invalidates it).
  static void clear(String key) {
    _store.remove(key);
    _stamps.remove(key);
  }

  /// Wipes everything. Called on logout / session expiry.
  static void clearAll() {
    _store.clear();
    _stamps.clear();
  }
}
