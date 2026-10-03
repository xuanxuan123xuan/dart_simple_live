import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/follow_user/tv_follow_grid_layout.dart';

void main() {
  group('TvFollowGridLayout', () {
    test('common TV logical viewports stay within the 4 to 6 column range', () {
      final cases = <({double width, double height})>[
        (width: 1280, height: 720),
        (width: 1920, height: 1080),
        (width: 2560, height: 1440),
        (width: 3840, height: 2160),
        (width: 1728, height: 972),
      ];

      for (final viewport in cases) {
        final scale = viewport.width / 1920;
        final layout = TvFollowGridLayout.resolve(
          availableWidth: viewport.width - 96 * scale,
          availableHeight: viewport.height - 250 * scale,
          density: TvFollowCardDensity.auto,
          showLiveCover: true,
          crossAxisSpacing: 24 * scale,
          mainAxisSpacing: 20 * scale,
          detailsExtent: 96 * scale,
        );

        expect(
          layout.crossAxisCount,
          inInclusiveRange(
            TvFollowGridLayout.minimumColumns,
            TvFollowGridLayout.maximumColumns,
          ),
          reason: '${viewport.width}x${viewport.height}',
        );
        expect(
          layout.mainAxisExtent,
          closeTo(layout.itemWidth / (16 / 9) + 96 * scale, 0.001),
        );
      }
    });

    test('auto density chooses the largest cards that fit three rows', () {
      final layout = TvFollowGridLayout.resolve(
        availableWidth: 1824,
        availableHeight: 830,
        density: TvFollowCardDensity.auto,
        showLiveCover: true,
      );

      expect(layout.crossAxisCount, 6);
      expect(
        layout.mainAxisExtent,
        closeTo(
          layout.itemWidth / TvFollowGridLayout.coverAspectRatio +
              TvFollowGridLayout.cardDetailsExtent,
          0.001,
        ),
      );
      expect(layout.mainAxisExtent * 3 + 40, lessThanOrEqualTo(830));
    });

    test('auto density can keep five columns when height allows it', () {
      final layout = TvFollowGridLayout.resolve(
        availableWidth: 2464,
        availableHeight: 1250,
        density: TvFollowCardDensity.auto,
        showLiveCover: true,
        crossAxisSpacing: 32,
        mainAxisSpacing: 26,
        detailsExtent: 128,
      );

      expect(layout.crossAxisCount, 5);
      expect(layout.mainAxisExtent * 3 + 52, lessThanOrEqualTo(1250));
    });

    test('manual densities use comfortable and dense column targets', () {
      final comfortable = TvFollowGridLayout.resolve(
        availableWidth: 1824,
        availableHeight: 800,
        density: TvFollowCardDensity.comfortable,
        showLiveCover: true,
      );
      final dense = TvFollowGridLayout.resolve(
        availableWidth: 1824,
        availableHeight: 800,
        density: TvFollowCardDensity.dense,
        showLiveCover: true,
      );

      expect(comfortable.crossAxisCount, 4);
      expect(dense.crossAxisCount, 6);
      expect(comfortable.itemWidth, greaterThan(dense.itemWidth));
    });

    test('invalid persisted density falls back to auto', () {
      expect(
        TvFollowCardDensity.fromStorage('legacy'),
        TvFollowCardDensity.auto,
      );
    });
  });
}
