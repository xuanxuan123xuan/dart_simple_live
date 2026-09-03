/*
 * 鸿蒙服务卡片 UI。
 * 快照字段由 FollowFormAbility 通过 formBindingData 注入，
 * 卡片不联网，只渲染 Flutter 侧写入的开播状态快照。
 */
interface FollowItem {
  siteId: string;
  roomId: string;
  userName: string;
  face: string;
  roomTitle: string;
  living: boolean;
  special: boolean;
}

interface Snapshot {
  updatedAt: number;
  items: FollowItem[];
}

function parseSnapshot(raw: string): Snapshot | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as Snapshot;
  } catch {
    return null;
  }
}

function formatAge(ts: number): string {
  const diff = Math.floor((Date.now() - ts) / 1000);
  if (diff < 60) return '刚刚';
  if (diff < 3600) return `${Math.floor(diff / 60)} 分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 小时前`;
  return `${Math.floor(diff / 86400)} 天前`;
}

@Entry
@Component
struct FollowCard {
  @LocalStorageProp('snapshot') snapshot: string = '';

  build() {
    Column({ space: 0 }) {
      // 标题栏
      Row() {
        Text('SimpleLive')
          .fontSize(12)
          .fontColor('#FFFFFFFF')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
        Blank()
        if (parseSnapshot(this.snapshot)) {
          Text(formatAge(parseSnapshot(this.snapshot)!.updatedAt))
            .fontSize(10)
            .fontColor('#99FFFFFF')
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 4 })

      if (!parseSnapshot(this.snapshot) || parseSnapshot(this.snapshot)!.items.length === 0) {
        // 空态
        Column() {
          Text('暂无关注')
            .fontSize(13)
            .fontColor('#99FFFFFF')
        }
        .width('100%')
        .flexGrow(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // 最多渲染 4 条（2×2 / 4×2 卡片尺寸下合适）
        ForEach(parseSnapshot(this.snapshot)!.items.slice(0, 4), (item: FollowItem) => {
          Row({ space: 8 }) {
            // 头像 + 开播圆点
            Stack({ alignContent: Alignment.BottomEnd }) {
              Image(item.face)
                .width(32)
                .height(32)
                .borderRadius(16)
                .objectFit(ImageFit.Cover)
                .alt($r('app.media.icon'))
              if (item.living) {
                Circle({ width: 10, height: 10 })
                  .fill('#FF3B3B')
                  .stroke('#222222')
                  .strokeWidth(1.5)
              }
            }
            .width(32)
            .height(32)

            // 昵称 + 直播间标题
            Column({ space: 1 }) {
              Text(item.userName)
                .fontSize(13)
                .fontColor('#FFFFFFFF')
                .fontWeight(item.living ? FontWeight.Medium : FontWeight.Regular)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.living && item.roomTitle) {
                Text(item.roomTitle)
                  .fontSize(10)
                  .fontColor('#BFFFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              } else {
                Text('未开播')
                  .fontSize(10)
                  .fontColor('#66FFFFFF')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .flexGrow(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .onClick(() => {
            // 点击跳转到对应直播间，复用通知的 want 参数格式。
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: {
                siteId: item.siteId,
                roomId: item.roomId,
              }
            });
          })
        }, (item: FollowItem) => `${item.siteId}_${item.roomId}`)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#CC1A1A2E')
    .borderRadius(16)
    .clip(true)
  }
}
