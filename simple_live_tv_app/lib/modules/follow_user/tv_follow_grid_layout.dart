import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum TvFollowCardDensity {
  auto('auto'),
  comfortable('comfortable'),
  dense('dense');

  const TvFollowCardDensity(this.storageValue);

  final String storageValue;

  static TvFollowCardDensity fromStorage(String value) {
    return values.firstWhere(
      (density) => density.storageValue == value,
      orElse: () => TvFollowCardDensity.auto,
    );
  }
}

@immutable
class TvFollowGridLayout {
  const TvFollowGridLayout({
    required this.crossAxisCount,
    required this.itemWidth,
    required this.mainAxisExtent,
  });

  static const double coverAspectRatio = 16 / 9;
  static const int minimumColumns = 4;
  static const int maximumColumns = 6;
  static const double cardDetailsExtent = 96;

  final int crossAxisCount;
  final double itemWidth;
  final double mainAxisExtent;

  static TvFollowGridLayout resolve({
    required double availableWidth,
    required double availableHeight,
    required TvFollowCardDensity density,
    required bool showLiveCover,
    double crossAxisSpacing = 24,
    double mainAxisSpacing = 20,
    double detailsExtent = cardDetailsExtent,
    double avatarMinimumExtent = 168,
    double avatarMaximumExtent = 230,
  }) {
    final safeWidth = math.max(0.0, availableWidth);
    final safeHeight = math.max(0.0, availableHeight);

    int columns;
    switch (density) {
      case TvFollowCardDensity.comfortable:
        columns = minimumColumns;
        break;
      case TvFollowCardDensity.dense:
        columns = maximumColumns;
        break;
      case TvFollowCardDensity.auto:
        columns = maximumColumns;
        for (var candidate = minimumColumns;
            candidate <= maximumColumns;
            candidate++) {
          final width = _itemWidth(safeWidth, candidate, crossAxisSpacing);
          final extent = _itemExtent(
            width,
            showLiveCover: showLiveCover,
            detailsExtent: detailsExtent,
            avatarMinimumExtent: avatarMinimumExtent,
            avatarMaximumExtent: avatarMaximumExtent,
          );
          final threeRowsExtent = extent * 3 + mainAxisSpacing * 2;
          if (threeRowsExtent <= safeHeight) {
            columns = candidate;
            break;
          }
        }
        break;
    }

    final itemWidth = _itemWidth(safeWidth, columns, crossAxisSpacing);
    return TvFollowGridLayout(
      crossAxisCount: columns,
      itemWidth: itemWidth,
      mainAxisExtent: _itemExtent(
        itemWidth,
        showLiveCover: showLiveCover,
        detailsExtent: detailsExtent,
        avatarMinimumExtent: avatarMinimumExtent,
        avatarMaximumExtent: avatarMaximumExtent,
      ),
    );
  }

  static double _itemWidth(
    double availableWidth,
    int columns,
    double spacing,
  ) {
    return math.max(0.0, availableWidth - spacing * (columns - 1)) / columns;
  }

  static double _itemExtent(
    double itemWidth, {
    required bool showLiveCover,
    required double detailsExtent,
    required double avatarMinimumExtent,
    required double avatarMaximumExtent,
  }) {
    if (showLiveCover) {
      return itemWidth / coverAspectRatio + detailsExtent;
    }
    return math.min(
      avatarMaximumExtent,
      math.max(avatarMinimumExtent, itemWidth * 0.62),
    );
  }
}
