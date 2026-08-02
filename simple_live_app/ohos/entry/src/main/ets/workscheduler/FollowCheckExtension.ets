import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { preferences } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { http } from '@kit.NetworkKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FollowCheckExtension';
const DOMAIN = 0x1208;
const PREFS_NAME = 'simple_live_widget';
const SNAPSHOT_KEY = 'follow_snapshot';
const LAST_NOTIFIED_KEY = 'last_notified_ids';
const BUNDLE_NAME = 'com.simplelive.app';
const ABILITY_NAME = 'EntryAbility';

interface FollowItem {
  siteId: string;
  roomId: string;
  userName: string;
  face: string;
  special: boolean;
  needsSign: boolean;
  living: boolean;
}

interface Snapshot {
  updatedAt: number;
  items: FollowItem[];
}

/** 仅支持无签名直接查询的平台：虎牙/斗鱼/B站 */
const QUERYABLE_SITES: Record<string, string> = {
  'huya':    'https://m.huya.com/lapi/live/getInfo/{roomId}',
  'douyu':   'https://www.douyu.com/lapi/live/getH5Play/{roomId}',
  'bilibili': 'https://api.live.bilibili.com/room/v1/Room/get_info?room_id={roomId}',
};

function isLivingResponse(siteId: string, body: string): boolean {
  try {
    const json = JSON.parse(body);
    if (siteId === 'huya') {
      return json?.data?.stream?.living === 1;
    }
    if (siteId === 'douyu') {
      return json?.data?.room_status === '1';
    }
    if (siteId === 'bilibili') {
      return json?.data?.live_status === 1;
    }
  } catch { /* ignore */ }
  return false;
}

async function queryLiveStatus(siteId: string, roomId: string): Promise<boolean> {
  const urlTemplate = QUERYABLE_SITES[siteId];
  if (!urlTemplate) return false;
  const url = urlTemplate.replace('{roomId}', roomId);
  try {
    const resp = await http.createHttp().request(url, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': 'Mozilla/5.0' },
      connectTimeout: 8000,
      readTimeout: 8000,
    });
    if (resp.responseCode !== 200) return false;
    return isLivingResponse(siteId, resp.result as string);
  } catch {
    return false;
  }
}

async function buildWantAgent(siteId: string, roomId: string): Promise<WantAgent> {
  const agentInfo: wantAgent.WantAgentInfo = {
    wants: [{
      bundleName: BUNDLE_NAME,
      abilityName: ABILITY_NAME,
      parameters: { roomId, siteId },
    }],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 2000,
    actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
  };
  return wantAgent.getWantAgent(agentInfo);
}

export default class FollowCheckExtension extends WorkSchedulerExtensionAbility {
  async onWorkStart(workInfo: workScheduler.WorkInfo): Promise<void> {
    hilog.info(DOMAIN, TAG, `onWorkStart workId=${workInfo.workId}`);
    try {
      const appCtx = this.context.getApplicationContext();
      const prefs = preferences.getPreferencesSync(appCtx, { name: PREFS_NAME });

      const raw = prefs.getSync(SNAPSHOT_KEY, '') as string;
      if (!raw) return;

      const snapshot = JSON.parse(raw) as Snapshot;
      // 只处理「特别关注」且「无需签名」的条目
      const targets = snapshot.items.filter(
        (item) => item.special && !item.needsSign && QUERYABLE_SITES[item.siteId]
      );
      if (targets.length === 0) return;

      const prevNotifiedRaw = prefs.getSync(LAST_NOTIFIED_KEY, '[]') as string;
      const prevNotified: string[] = JSON.parse(prevNotifiedRaw);

      const nowNotified: string[] = [];
      let notifId = 3000;

      for (const item of targets) {
        const id = `${item.siteId}_${item.roomId}`;
        const living = await queryLiveStatus(item.siteId, item.roomId);
        if (living) {
          nowNotified.push(id);
          // 仅在「上次未通知、这次开播了」时发通知，避免重复打扰
          if (!prevNotified.includes(id)) {
            const agent = await buildWantAgent(item.siteId, item.roomId);
            await notificationManager.publish({
              id: notifId++,
              content: {
                notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
                normal: {
                  title: '特别关注开播了',
                  text: `${item.userName} 正在直播`,
                  additionalText: 'Simple Live',
                }
              },
              wantAgent: agent,
            });
          }
        }
      }

      // 更新已通知列表 + 刷新快照中的 living 字段
      await prefs.put(LAST_NOTIFIED_KEY, JSON.stringify(nowNotified));
      // 同步更新快照（后台查到的新鲜状态写回，卡片下次刷新时读取）
      const now = Date.now();
      const updatedItems = snapshot.items.map((item) => {
        const id = `${item.siteId}_${item.roomId}`;
        const checked = targets.find(t => `${t.siteId}_${t.roomId}` === id);
        if (checked) {
          return { ...item, living: nowNotified.includes(id) };
        }
        return item;
      });
      await prefs.put(SNAPSHOT_KEY, JSON.stringify({ updatedAt: now, items: updatedItems }));
      await prefs.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `onWorkStart error: ${e}`);
    }
  }

  onWorkStop(workInfo: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, `onWorkStop workId=${workInfo.workId}`);
  }
}
