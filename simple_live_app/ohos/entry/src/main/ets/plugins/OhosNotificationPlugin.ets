import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { WantAgent, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';

const CHANNEL_NAME = 'simple_live/live_notifications';
const BUNDLE_NAME = 'com.simplelive.app';
const ABILITY_NAME = 'EntryAbility';

export interface LiveNotificationTarget {
  roomId: string;
  siteId: string;
}

export default class OhosNotificationPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private pendingTarget?: LiveNotificationTarget;

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

    const agentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: BUNDLE_NAME,
        abilityName: ABILITY_NAME,
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
