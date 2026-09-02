import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/net_image.dart';

enum FollowUserItemStyle {
  defaultList,
  compactList,
  card,
}

class FollowUserItem extends StatelessWidget {
  final FollowUser item;
  final Function()? onRemove;
  final Function()? onSpecialTap;
  final Function()? onTap;
  final Function()? onLongPress;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;
  final bool playing;
  final bool showSpecialMark;
  final bool showLiveCover;
  final FollowUserItemStyle style;

  const FollowUserItem({
    required this.item,
    this.onRemove,
    this.onSpecialTap,
    this.onTap,
    this.onLongPress,
    this.onLongPressEnd,
    this.onLongPressCancel,
    this.playing = false,
    this.showSpecialMark = false,
    this.showLiveCover = false,
    this.style = FollowUserItemStyle.defaultList,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return _FollowUserLongPressSurface(
      onLongPress: onLongPress,
      onLongPressEnd: onLongPressEnd,
      onLongPressCancel: onLongPressCancel,
      builder: (handleLongPress) => Obx(() {
        switch (style) {
          case FollowUserItemStyle.compactList:
            return _buildListCard(
              context,
              compact: true,
              handleLongPress: handleLongPress,
            );
          case FollowUserItemStyle.card:
            return _buildPreviewCard(
              context,
              handleLongPress: handleLongPress,
            );
          case FollowUserItemStyle.defaultList:
            return _buildListCard(
              context,
              compact: false,
              handleLongPress: handleLongPress,
            );
        }
      }),
    );
  }

  Widget _buildListCard(
    BuildContext context, {
    required bool compact,
    required VoidCallback? handleLongPress,
  }) {
    if (!showLiveCover) {
      return _buildAvatarListCard(
        context,
        compact: compact,
        handleLongPress: handleLongPress,
      );
    }
    final theme = Theme.of(context);
    final coverWidth = compact ? 122.0 : 152.0;
    final coverHeight = coverWidth * 9 / 16;
    final avatarSize = compact ? 34.0 : 40.0;
    final avatarOverlap = avatarSize / 2;
    final radius = BorderRadius.circular(compact ? 14 : 16);
    final cardColor = _cardBackgroundColor(theme);
    final titleStyle = compact
        ? theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.05,
          )
        : theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.05,
          );
    final roomTitleStyle =
        (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.05,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.grey.shade600,
      height: 1.05,
    );
    final liveDuration = _liveDurationText();
    final platformText =
        liveDuration.isEmpty ? _site.name : "${_site.name} · $liveDuration";
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final metadataTextScaler = TextScaler.linear(
      textScale > 1.1 ? 1.1 : textScale,
    );
    Widget buildPlatformRow() {
      return Row(
        children: [
          Image.asset(
            _site.logo,
            width: compact ? 14 : 16,
            height: compact ? 14 : 16,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              platformText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
          ),
          if (playing) ...[
            const SizedBox(width: 6),
            Text(
              "正在观看",
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
                height: 1.05,
              ),
            ),
          ],
          if (showSpecialMark && item.isSpecialFollow)
            const Padding(
              padding: EdgeInsets.only(left: 5),
              child: Icon(
                Icons.star,
                color: Colors.amber,
                size: 15,
              ),
            ),
        ],
      );
    }

    return Material(
      color: cardColor,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: handleLongPress,
        child: Container(
          foregroundDecoration: _cardFrameDecoration(theme, radius),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: coverWidth + avatarOverlap,
                height: coverHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(
                      width: coverWidth,
                      height: coverHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(compact ? 10 : 12),
                        child: _buildCover(
                          context,
                          radius: compact ? 10 : 12,
                          showTitleOverlay: false,
                          compact: compact,
                        ),
                      ),
                    ),
                    Positioned(
                      left: coverWidth - avatarOverlap,
                      top: (coverHeight - avatarSize) / 2,
                      child: _buildFramedAvatar(
                        size: avatarSize,
                        borderColor: cardColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 6 : 8),
              Expanded(
                child: SizedBox(
                  height: coverHeight,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: metadataTextScaler,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: item.liveStatus.value == 2
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.userName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: titleStyle,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _displayRoomTitle(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: roomTitleStyle,
                                    ),
                                    const SizedBox(height: 2),
                                    buildPlatformRow(),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.userName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.left,
                                      style: titleStyle,
                                    ),
                                    const SizedBox(height: 2),
                                    buildPlatformRow(),
                                  ],
                                ),
                        ),
                        SizedBox(width: compact ? 2 : 4),
                        _buildActionArea(
                          context,
                          compact: true,
                          vertical: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarListCard(
    BuildContext context, {
    required bool compact,
    required VoidCallback? handleLongPress,
  }) {
    final theme = Theme.of(context);
    final avatarSize = compact ? 48.0 : 58.0;
    final radius = BorderRadius.circular(compact ? 12 : 14);
    final titleStyle = compact
        ? theme.textTheme.titleSmall
        : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.grey.shade600,
    );
    return Material(
      color: _cardBackgroundColor(theme),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: handleLongPress,
        child: Container(
          foregroundDecoration: _cardFrameDecoration(theme, radius),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          child: Row(
            children: [
              NetImage(
                item.face,
                width: avatarSize,
                height: avatarSize,
                borderRadius: avatarSize / 2,
              ),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusDot(),
                        const SizedBox(width: 4),
                        Text(
                          getStatus(item.liveStatus.value),
                          style: subtitleStyle,
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 4 : 6),
                    Row(
                      children: [
                        Image.asset(
                          _site.logo,
                          width: compact ? 16 : 18,
                          height: compact ? 16 : 18,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _site.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: subtitleStyle,
                          ),
                        ),
                        if (_liveDurationText().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _liveDurationText(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtitleStyle,
                            ),
                          ),
                        ],
                        if (playing) ...[
                          const SizedBox(width: 8),
                          Text(
                            "正在观看",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 6 : 10),
              _buildActionArea(
                context,
                compact: compact,
                vertical: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(
    BuildContext context, {
    required VoidCallback? handleLongPress,
  }) {
    if (!showLiveCover) {
      return _buildAvatarCard(
        context,
        handleLongPress: handleLongPress,
      );
    }
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(16);
    final cardColor = _cardBackgroundColor(theme);
    const avatarSize = 44.0;
    const avatarOverlap = 16.0;
    const contentInset = 12.0;
    const avatarNameOffset = avatarSize + 8;
    final showHeaderUserName = item.liveStatus.value == 2;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.grey.shade600,
      height: 1.15,
    );
    return Material(
      color: cardColor,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: handleLongPress,
        child: Container(
          foregroundDecoration: _cardFrameDecoration(theme, radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildCover(
                      context,
                      radius: 0,
                      showTitleOverlay: false,
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: -avatarOverlap,
                    child: _buildFramedAvatar(
                      size: avatarSize,
                      borderColor: cardColor,
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _buildCoverActions(context),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    contentInset,
                    2,
                    contentInset,
                    4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 操作按钮已移到封面右上角，这一行整宽留给主播名；未开播时
                      // 名字下移到标题位，这里仅为头像下沉预留高度。
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: avatarOverlap + 4,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(width: avatarNameOffset),
                            if (showHeaderUserName)
                              Expanded(
                                child: Text(
                                  item.userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.05,
                                  ),
                                ),
                              )
                            else
                              const Spacer(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        fit: FlexFit.tight,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _cardRoomText(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Image.asset(_site.logo, width: 14, height: 14),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _site.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtitleStyle,
                            ),
                          ),
                          if (playing) ...[
                            const SizedBox(width: 8),
                            Text(
                              "正在观看",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                          ],
                          // 特别关注状态由封面右上角的星标按钮呈现，此处不再重复。
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 封面右上角的操作条：特别关注 + 取关。
  ///
  /// 放在封面上而非正文，是为了让名字行拿到整宽（小屏开启星标后名字会被挤成
  /// 省略号），同时不受正文行高约束，点击区可以保持 36px。
  Widget _buildCoverActions(BuildContext context) {
    const buttonSize = 36.0;
    final children = <Widget>[
      if (showSpecialMark && onSpecialTap != null)
        _buildCoverActionButton(
          size: buttonSize,
          tooltip: item.isSpecialFollow ? "取消特别关注" : "特别关注",
          onPressed: onSpecialTap,
          icon: item.isSpecialFollow ? Icons.star : Icons.star_border,
          color: item.isSpecialFollow ? Colors.amber : Colors.white,
        )
      else if (showSpecialMark && item.isSpecialFollow)
        const SizedBox.square(
          dimension: buttonSize,
          child: Center(
            child: Icon(Icons.star, color: Colors.amber, size: 18),
          ),
        ),
      if (onRemove != null)
        _buildCoverActionButton(
          size: buttonSize,
          tooltip: "取消关注",
          onPressed: onRemove,
          icon: Remix.dislike_line,
          color: Colors.white,
        ),
    ];
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(82),
        borderRadius: BorderRadius.circular(buttonSize / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildCoverActionButton({
    required double size,
    required String tooltip,
    required IconData icon,
    required Color color,
    required Function()? onPressed,
  }) {
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 18,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const CircleBorder(),
        ),
        onPressed: onPressed,
        icon: Icon(icon, color: color),
      ),
    );
  }

  Widget _buildFramedAvatar({
    required double size,
    required Color borderColor,
  }) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: borderColor,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: NetImage(
        item.face,
        width: size - 4,
        height: size - 4,
        borderRadius: (size - 4) / 2,
      ),
    );
  }

  Widget _buildAvatarCard(
    BuildContext context, {
    required VoidCallback? handleLongPress,
  }) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(16);
    return Material(
      color: _cardBackgroundColor(theme),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: handleLongPress,
        child: Container(
          foregroundDecoration: _cardFrameDecoration(theme, radius),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NetImage(
                item.face,
                width: 72,
                height: 72,
                borderRadius: 36,
              ),
              const SizedBox(height: 12),
              Text(
                item.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Image.asset(_site.logo, width: 16, height: 16),
                  Text(
                    _site.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  _buildInfoChip(
                    context,
                    label: getStatus(item.liveStatus.value),
                    active: item.liveStatus.value == 2,
                  ),
                  if (playing)
                    _buildInfoChip(
                      context,
                      label: "正在观看",
                      active: true,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _buildActionArea(
                context,
                compact: true,
                vertical: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _cardBackgroundColor(ThemeData theme) {
    return theme.colorScheme.surface.withAlpha(
      theme.brightness == Brightness.dark ? 182 : 214,
    );
  }

  BoxDecoration _cardFrameDecoration(
    ThemeData theme,
    BorderRadius radius,
  ) {
    final borderColor = playing
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withAlpha(
            theme.brightness == Brightness.dark ? 175 : 145,
          );
    return BoxDecoration(
      border: Border.all(
        color: borderColor,
        width: playing ? 2 : 1,
      ),
      borderRadius: radius,
    );
  }

  Widget _buildCover(
    BuildContext context, {
    required double radius,
    bool showTitleOverlay = true,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    if (item.liveStatus.value != 2) {
      final isUnconfirmed = item.liveStatus.value == 0;
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          isUnconfirmed ? "未确认" : "未直播",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (compact
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleMedium)
              ?.copyWith(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final coverImage = _coverImage;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: coverImage.isEmpty
              ? Center(
                  child: Text(
                    "直播封面补齐中",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                )
              : NetImage(
                  coverImage,
                  fit: BoxFit.cover,
                  borderRadius: radius,
                  clearMemoryCacheWhenDispose: true,
                  imageCacheName: NetImage.liveCoverCacheName,
                  cacheMaxAge: const Duration(minutes: 10),
                ),
        ),
        if (showTitleOverlay)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(
              _displayRoomTitle(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    blurRadius: 8,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusDot({double size = 8}) {
    final active = item.liveStatus.value == 2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? Colors.green : Colors.grey,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required String label,
    required bool active,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary.withAlpha(28)
            : Colors.black.withAlpha(20),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: active ? theme.colorScheme.primary : Colors.grey.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildActionArea(
    BuildContext context, {
    required bool compact,
    required bool vertical,
  }) {
    final iconSize = compact ? 18.0 : 20.0;
    // M3 的 IconButton 以 minimumSize(48) + visualDensity 结算尺寸，下面的
    // constraints 不生效，压到 28px 必须走 tapTargetSize.shrinkWrap。
    Widget constrainVerticalAction(Widget child) {
      return vertical ? SizedBox.square(dimension: 28, child: child) : child;
    }

    final children = <Widget>[
      if (showSpecialMark && onSpecialTap != null)
        constrainVerticalAction(
          IconButton(
            tooltip: item.isSpecialFollow ? "取消特别关注" : "特别关注",
            iconSize: iconSize,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: vertical
                ? const BoxConstraints()
                : const BoxConstraints(minWidth: 28, minHeight: 28),
            style: vertical
                ? IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                : null,
            onPressed: onSpecialTap,
            icon: Icon(
              item.isSpecialFollow ? Icons.star : Icons.star_border,
              color: item.isSpecialFollow ? Colors.amber : null,
            ),
          ),
        )
      else if (showSpecialMark && item.isSpecialFollow)
        Icon(
          Icons.star,
          color: Colors.amber,
          size: iconSize,
        ),
      if (onRemove != null)
        constrainVerticalAction(
          IconButton(
            iconSize: iconSize,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: vertical
                ? const BoxConstraints()
                : const BoxConstraints(minWidth: 28, minHeight: 28),
            style: vertical
                ? IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                : null,
            onPressed: onRemove,
            icon: const Icon(Remix.dislike_line),
          ),
        ),
    ];
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          );
  }

  Site get _site => Sites.allSites[item.siteId]!;

  String get _coverImage {
    if (item.liveStatus.value != 2) {
      return "";
    }
    return item.roomCover.trim();
  }

  String _displayRoomTitle() {
    final title = item.roomTitle.trim();
    if (item.liveStatus.value == 2) {
      if (title.isNotEmpty) {
        return title;
      }
      return showLiveCover ? "直播封面与标题补齐中" : item.userName;
    }
    return item.userName;
  }

  String _cardRoomText() {
    return item.liveStatus.value == 2 ? _displayRoomTitle() : item.userName;
  }

  String getStatus(int status) {
    if (status == 2) {
      return "直播中";
    }
    if (status == 0) {
      return "未确认";
    }
    return "未开播";
  }

  String _liveDurationText() {
    final duration = formatLiveDuration(item.liveStartTime);
    if (duration.isEmpty) {
      return "";
    }
    return "开播 $duration";
  }

  String formatLiveDuration(String? startTimeStampString) {
    if (startTimeStampString == null ||
        startTimeStampString.isEmpty ||
        startTimeStampString == "0") {
      return "";
    }
    try {
      final startTimeStamp = int.parse(startTimeStampString);
      final currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final durationInSeconds = currentTimeStamp - startTimeStamp;
      final hours = durationInSeconds ~/ 3600;
      final minutes = (durationInSeconds % 3600) ~/ 60;
      final hourText = hours > 0 ? '$hours小时' : '';
      final minuteText = minutes > 0 ? '$minutes分钟' : '';
      if (hours == 0 && minutes == 0) {
        return "不足1分钟";
      }
      return '$hourText$minuteText';
    } catch (e) {
      Log.logPrint('格式化开播时长出错: $e');
      return "";
    }
  }
}

typedef _FollowUserLongPressBuilder = Widget Function(
  VoidCallback? handleLongPress,
);

/// `InkWell` only exposes the moment a long press is recognized. This wrapper
/// keeps that visual/tap behavior while observing the raw pointer end/cancel
/// events needed by the temporary live preview.
class _FollowUserLongPressSurface extends StatefulWidget {
  const _FollowUserLongPressSurface({
    required this.builder,
    this.onLongPress,
    this.onLongPressEnd,
    this.onLongPressCancel,
  });

  final _FollowUserLongPressBuilder builder;
  final VoidCallback? onLongPress;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;

  @override
  State<_FollowUserLongPressSurface> createState() =>
      _FollowUserLongPressSurfaceState();
}

class _FollowUserLongPressSurfaceState
    extends State<_FollowUserLongPressSurface> {
  bool _longPressActive = false;

  void _handleLongPress() {
    _longPressActive = true;
    widget.onLongPress?.call();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_longPressActive) return;
    _longPressActive = false;
    widget.onLongPressEnd?.call(
      LongPressEndDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
      ),
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (!_longPressActive) return;
    _longPressActive = false;
    widget.onLongPressCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.builder(
        widget.onLongPress == null ? null : _handleLongPress,
      ),
    );
  }
}
