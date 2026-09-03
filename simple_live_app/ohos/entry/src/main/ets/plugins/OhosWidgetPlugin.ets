import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';

const CHANNEL_NAME = 'simple_live/ohos_widget';
const PREFS_NAME = 'simple_live_widget';
const SNAPSHOT_KEY = 'follow_snapshot';

/** 后台关注检查的固定 workId。 */
const FOLLOW_CHECK_WORK_ID = 1207;
/** 系统对重复任务的最小间隔约 2 小时，低于此值会被拒绝。 */
const FOLLOW_CHECK_INTERVAL_MS = 2 * 60 * 60 * 1000;

export default class OhosWidgetPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'OhosWidgetPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'updateSnapshot') {
      this.updateSnapshot(call, result);
    } else if (call.method === 'startFollowCheck') {
      this.startFollowCheck(result);
    } else if (call.method === 'stopFollowCheck') {
      this.stopFollowCheck(result);
    } else {
      result.notImplemented();
    }
  }

  private startFollowCheck(result: MethodResult): void {
    const workInfo: workScheduler.WorkInfo = {
      workId: FOLLOW_CHECK_WORK_ID,
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: 'FollowCheckExtension',
      networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
      repeatCycleTime: FOLLOW_CHECK_INTERVAL_MS,
      isRepeat: true,
      isPersisted: true
    };
    try {
      workScheduler.startWork(workInfo);
      result.success(true);
    } catch (error) {
      result.error('work_start_failed', `${error}`, null);
    }
  }

  private stopFollowCheck(result: MethodResult): void {
    const workInfo: workScheduler.WorkInfo = {
      workId: FOLLOW_CHECK_WORK_ID,
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: 'FollowCheckExtension'
    };
    try {
      workScheduler.stopWork(workInfo, true);
      result.success(true);
    } catch (error) {
      // 任务本来就没在跑时也会抛，视为已停止。
      result.success(false);
    }
  }

  private async updateSnapshot(call: MethodCall, result: MethodResult): Promise<void> {
    const payload: string = call.argument('payload');
    if (!payload) {
      result.error('invalid_arguments', 'payload is empty', null);
      return;
    }
    try {
      // 写入 preferences，供 FormExtensionAbility 读取。
      const prefs = await preferences.getPreferences(this.context, PREFS_NAME);
      await prefs.put(SNAPSHOT_KEY, payload);
      await prefs.flush();

      // 通知卡片刷新：API 26 中 notifyFormsChange 已移除，
      // 卡片会通过 FormExtensionAbility.onUpdateForm 自动刷新。

      result.success(null);
    } catch (error) {
      result.error('snapshot_update_failed', `${error}`, null);
    }
  }
}
