/// Helper mixin for pull-to-refresh functionality
/// Provides a centralized way to handle refresh logic across screens
mixin RefreshHelper {
  bool _isRefreshing = false;

  /// Check if a refresh is currently in progress
  bool get isRefreshing => _isRefreshing;

  /// Execute refresh with duplicate call prevention
  /// Returns a Future that completes when refresh is done
  Future<void> executeRefresh(Future<void> Function() refreshFunction) async {
    if (_isRefreshing) {
      return; // Prevent duplicate calls
    }

    try {
      _isRefreshing = true;
      await refreshFunction();
    } finally {
      _isRefreshing = false;
    }
  }
}
