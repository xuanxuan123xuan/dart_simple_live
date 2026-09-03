import { FormExtensionAbility, formBindingData, formProvider, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FollowFormAbility';
const DOMAIN = 0x1207;
const PREFS_NAME = 'simple_live_widget';
const SNAPSHOT_KEY = 'follow_snapshot';

export default class FollowFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm');
    const snapshot = this.readSnapshot();
    return formBindingData.createFormBindingData({ snapshot });
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, `onUpdateForm: ${formId}`);
    const snapshot = this.readSnapshot();
    formProvider.updateForm(formId, formBindingData.createFormBindingData({ snapshot }))
      .catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, `updateForm failed: ${err.code} ${err.message}`);
      });
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, `onRemoveForm: ${formId}`);
  }

  onFormEvent(formId: string, message: string): void {
    // 卡片内「刷新」按钮触发。把请求透传给主 Ability 去拉新数据没有意义
    // （需要 Flutter 引擎），此处只重读 preferences 刷新当前快照。
    hilog.info(DOMAIN, TAG, `onFormEvent: ${formId} ${message}`);
    this.onUpdateForm(formId);
  }

  private readSnapshot(): string {
    try {
      // FormExtensionAbility 的 context 是 FormExtensionContext，
      // getApplicationContext() 返回应用级 context，可访问共享 preferences。
      const appCtx = this.context.getApplicationContext();
      // getPreferencesSync 在 API 12+ 可用，确保与 OhosWidgetPlugin 同名同路径。
      const prefs = preferences.getPreferencesSync(appCtx, { name: PREFS_NAME });
      const raw = prefs.getSync(SNAPSHOT_KEY, '');
      return typeof raw === 'string' ? raw : '';
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `readSnapshot failed: ${err}`);
      return '';
    }
  }
}
