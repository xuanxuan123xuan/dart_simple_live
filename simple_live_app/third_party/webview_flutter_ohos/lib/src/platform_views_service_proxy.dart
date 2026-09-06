// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Proxy that provides access to the platform views service.
///
/// This service allows creating and controlling platform-specific views.
@immutable
class PlatformViewsServiceProxy {
  /// Constructs a [PlatformViewsServiceProxy].
  const PlatformViewsServiceProxy();

  /// Proxy method for [PlatformViewsService.initExpensiveAndroidView].
  ExpensiveOhosViewController initExpensiveOhosView({
    required int id,
    required String viewType,
    required TextDirection layoutDirection,
    dynamic creationParams,
    MessageCodec<dynamic>? creationParamsCodec,
    VoidCallback? onFocus,
  }) {
    return PlatformViewsService.initExpensiveOhosView(
      id: id,
      viewType: viewType,
      layoutDirection: layoutDirection,
      creationParams: creationParams,
      creationParamsCodec: creationParamsCodec,
      onFocus: onFocus,
    );
  }

  /// Proxy method for [PlatformViewsService.initSurfaceAndroidView].
  SurfaceOhosViewController initSurfaceOhosView({
    required int id,
    required String viewType,
    required TextDirection layoutDirection,
    dynamic creationParams,
    MessageCodec<dynamic>? creationParamsCodec,
    VoidCallback? onFocus,
  }) {
    return PlatformViewsService.initSurfaceOhosView(
      id: id,
      viewType: viewType,
      layoutDirection: layoutDirection,
      creationParams: creationParams,
      creationParamsCodec: creationParamsCodec,
      onFocus: onFocus,
    );
  }
}
