class WindowsVideoAccelerationPolicy {
  static const _copyBackDecoders = <String, String>{
    'auto': 'auto-copy',
    'auto-safe': 'auto-copy',
    'yes': 'auto-copy',
    'd3d11va': 'd3d11va-copy',
    'dxva2': 'dxva2-copy',
    'nvdec': 'nvdec-copy',
    'cuda': 'cuda-copy',
    'vulkan': 'vulkan-copy',
  };

  static const _softwareOutputDecoders = <String>{
    'no',
    'auto-copy',
    'auto-copy-safe',
    'd3d11va-copy',
    'dxva2-copy',
    'nvdec-copy',
    'cuda-copy',
    'vulkan-copy',
  };

  static WindowsVideoAccelerationDecision resolve({
    required bool hardwareDecode,
    required bool renderingAcceleration,
    required String? requestedHwdec,
  }) {
    if (!hardwareDecode) {
      return const WindowsVideoAccelerationDecision(
        hwdec: 'no',
        sourceOverride: 'hardwareDecode:off',
      );
    }
    if (renderingAcceleration) {
      return WindowsVideoAccelerationDecision(hwdec: requestedHwdec);
    }

    final requested = requestedHwdec?.trim().toLowerCase();
    if (_softwareOutputDecoders.contains(requested)) {
      return WindowsVideoAccelerationDecision(hwdec: requested);
    }
    final copyBack = requested == null || requested.isEmpty
        ? 'auto-copy'
        : _copyBackDecoders[requested];
    if (copyBack != null) {
      return WindowsVideoAccelerationDecision(
        hwdec: copyBack,
        sourceOverride: 'renderAcceleration:copy-back',
      );
    }
    return const WindowsVideoAccelerationDecision(
      hwdec: 'no',
      sourceOverride: 'renderAcceleration:software-fallback',
    );
  }
}

class WindowsVideoAccelerationDecision {
  const WindowsVideoAccelerationDecision({required this.hwdec, this.sourceOverride});

  final String? hwdec;
  final String? sourceOverride;
}
