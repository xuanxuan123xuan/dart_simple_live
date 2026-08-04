import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { WantAgent, wantAgent, common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';

const CHANNEL_NAME = 'simple_live/live_notifications';

export interface LiveNotificationTarget {
  roomId: string;
  siteId: string;
}

export default class OhosNotificationPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel;
  private pendingTarget?: LiveNotificationTarget;
  private context?: common.UIAbilityContext;

  constructor(initialTarget?: LiveNotificationTarget) {
    this.pendingTarget = initialTarget;
  }

  getUniqueClassName(): string {
    return 'OhosNotificationPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.context = undefined;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'consumeNotificationTarget') {
      const target = this.pendingTarget;
      this.pendingTarget = undefined;
      result.success(target ?? null);
      return;
    }
    if (call.method === 'requestPermission') {
      this.requestPermission(result);
      return;
    }
    if (call.method === 'showLiveStart') {
      this.showLiveStart(call, result);
      return;
    }
    result.notImplemented();
  }

  setNotificationTarget(target: LiveNotificationTarget): void {
    this.pendingTarget = target;
    try {
      this.channel?.invokeMethod('notificationTargetChanged', null);
    } catch (_error) {
      // Flutter may still be starting. The pending target remains available
      // through consumeNotificationTarget after the first frame.
    }
  }

  private requestPermission(result: MethodResult): void {
    notificationManager.isNotificationEnabled()
      .then((enabled: boolean) => {
        if (enabled) {
          result.success(true);
          return;
        }
        notificationManager.requestEnableNotification()
          .then(() => result.success(true))
          .catch((error: Error) => {
            result.error('permission_denied', `${error}`, null);
          });
      })
      .catch((error: Error) => {
        result.error('permission_failed', `${error}`, null);
      });
  }

  private showLiveStart(call: MethodCall, result: MethodResult): void {
    const notificationId: number = call.argument('notificationId');
    const title: string = call.argument('title');
    const body: string = call.argument('body');
    const roomId: string = call.argument('roomId');
    const siteId: string = call.argument('siteId');
    if (!title || !body || !roomId || !siteId) {
      result.error('invalid_arguments', 'Live notification data is incomplete', null);
      return;
    }
    const context = this.context;
    if (context === undefined) {
      result.error('no_context', 'Ability context is unavailable', null);
      return;
    }

    const agentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
        parameters: {
          roomId: roomId,
          siteId: siteId
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: notificationId,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    wantAgent.getWantAgent(agentInfo)
      .then((agent: WantAgent) => {
        const request: notificationManager.NotificationRequest = {
          id: notificationId,
          notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
          content: {
            notificationContentType:
              notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: {
              title: title,
              text: body
            }
          },
          wantAgent: agent
        };
        return notificationManager.publish(request);
      })
      .then(() => result.success(null))
      .catch((error: Error) => {
        result.error('publish_failed', `${error}`, null);
      });
  }
}
