/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import OhosWebCookiePlugin from '../plugins/OhosWebCookiePlugin';
import OhosMediaPlugin from '../plugins/OhosMediaPlugin';
import OhosNotificationPlugin, { LiveNotificationTarget } from '../plugins/OhosNotificationPlugin';
import OhosBackgroundPlaybackPlugin from '../plugins/OhosBackgroundPlaybackPlugin';
import OhosNetworkPlugin from '../plugins/OhosNetworkPlugin';
import OhosScanPlugin from '../plugins/OhosScanPlugin';
import OhosDocumentPlugin from '../plugins/OhosDocumentPlugin';
import OhosWidgetPlugin from '../plugins/OhosWidgetPlugin';

export default class EntryAbility extends FlutterAbility {
  private notificationPlugin?: OhosNotificationPlugin;
  private initialNotificationTarget?: LiveNotificationTarget;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.initialNotificationTarget = this.notificationTargetFromWant(want);
    super.onCreate(want, launchParam);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    const target = this.notificationTargetFromWant(want);
    if (target === undefined) return;
    if (this.notificationPlugin !== undefined) {
      this.notificationPlugin.setNotificationTarget(target);
    } else {
      this.initialNotificationTarget = target;
    }
  }
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new OhosWebCookiePlugin())
    flutterEngine.getPlugins()?.add(new OhosMediaPlugin())
    const notificationPlugin = new OhosNotificationPlugin(this.initialNotificationTarget)
    this.notificationPlugin = notificationPlugin
    this.initialNotificationTarget = undefined
    flutterEngine.getPlugins()?.add(notificationPlugin)
    flutterEngine.getPlugins()?.add(new OhosBackgroundPlaybackPlugin(this.context))
    flutterEngine.getPlugins()?.add(new OhosNetworkPlugin())
    flutterEngine.getPlugins()?.add(new OhosScanPlugin(this.context))
    flutterEngine.getPlugins()?.add(new OhosDocumentPlugin(this.context))
    flutterEngine.getPlugins()?.add(new OhosWidgetPlugin(this.context))
  }

  private notificationTargetFromWant(want: Want): LiveNotificationTarget | undefined {
    const parameters = want.parameters;
    if (parameters === undefined) return undefined;
    const roomIdValue = parameters['roomId'];
    const siteIdValue = parameters['siteId'];
    if (typeof roomIdValue !== 'string' || typeof siteIdValue !== 'string') {
      return undefined;
    }
    const roomId = roomIdValue.trim();
    const siteId = siteIdValue.trim();
    if (roomId.length === 0 || siteId.length === 0) return undefined;
    return {
      roomId: roomId,
      siteId: siteId
    };
  }
}
