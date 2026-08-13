import 'package:flutter/material.dart';

/// Global route observer for detecting when routes are pushed/popped.
/// Used so the dashboard can refresh once when user returns to it from another screen.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
