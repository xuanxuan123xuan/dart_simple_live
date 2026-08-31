import 'dart:math' as math;

class IosVideoOutputSize {
  final int width;
  final int height;

  const IosVideoOutputSize(this.width, this.height);

  @override
  bool operator ==(Object other) {
    return other is IosVideoOutputSize &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

IosVideoOutputSize? calculateIosVideoOutputSize({
  required int sourceWidth,
  required int sourceHeight,
  required double screenPhysicalWidth,
  required double screenPhysicalHeight,
}) =>
    calculateIosVideoOutputSizeWithinBounds(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      maxPhysicalWidth: screenPhysicalWidth,
      maxPhysicalHeight: screenPhysicalHeight,
    );

/// Calculates an even-sized video texture which fits an arbitrary physical
/// pixel boundary while preserving the source aspect ratio.
IosVideoOutputSize? calculateIosVideoOutputSizeWithinBounds({
  required int sourceWidth,
  required int sourceHeight,
  required double maxPhysicalWidth,
  required double maxPhysicalHeight,
}) {
  if (sourceWidth < 2 ||
      sourceHeight < 2 ||
      !maxPhysicalWidth.isFinite ||
      !maxPhysicalHeight.isFinite ||
      maxPhysicalWidth < 2 ||
      maxPhysicalHeight < 2) {
    return null;
  }

  final scale = math.min(
    1.0,
    math.min(
      maxPhysicalWidth / sourceWidth,
      maxPhysicalHeight / sourceHeight,
    ),
  );

  int toEvenDimension(double value) {
    final roundedDown = value.floor();
    if (roundedDown <= 2) {
      return 2;
    }
    return roundedDown.isEven ? roundedDown : roundedDown - 1;
  }

  return IosVideoOutputSize(
    toEvenDimension(sourceWidth * scale),
    toEvenDimension(sourceHeight * scale),
  );
}
