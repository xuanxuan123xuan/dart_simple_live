# screen_brightness

A Plugin for controlling screen brightness with application life cycle reset implemented.

This plugin only changes application brightness not system brightness. So no permission is needed for this plugin.

## Getting Started
### Install
Add the following lines in your pubspec.yaml file

```yaml
  screen_brightness: ^latest_version
```

latest_version:\
[![pub package](https://img.shields.io/pub/v/screen_brightness.svg)](https://pub.dartlang.org/packages/screen_brightness)

To adjust the system brightness on Android, add the following permission in your `AndroidManifest.xml` file
```xml
<!-- You must also ensure that the `xmlns:tools="http://schemas.android.com/tools"` namespace has been 
    added to your <manifest> tag
-->
<uses-permission android:name="android.permission.WRITE_SETTINGS" tools:ignore="ProtectedPermissions"/>
```



### API
#### System brightness
```dart
Future<double> get systemBrightness async {
  try {
    return await ScreenBrightness.instance.system;
  } catch (e) {
    print(e);
    throw 'Failed to get system brightness';
  }
}
```
#### Set system brightness
```dart
  Future<void> setSystemBrightness(double brightness) async {
  try {
    await ScreenBrightness.instance.setSystemScreenBrightness(brightness);
  } catch (e) {
    debugPrint(e.toString());
    throw 'Failed to set system brightness';
  }
}
```
#### Application brightness
```dart
Future<double> get applicationBrightness async {
  try {
    return await ScreenBrightness.instance.application;
  } catch (e) {
    print(e);
    throw 'Failed to get application brightness';
  }
}
```
#### Set application brightness
```dart
Future<void> setApplicationBrightness(double brightness) async {
  try {
    await ScreenBrightness.instance
        .setApplicationScreenBrightness(brightness);
  } catch (e) {
    debugPrint(e.toString());
    throw 'Failed to set application brightness';
  }
}
```
#### Reset application brightness
```dart
  Future<void> resetApplicationBrightness() async {
  try {
    await ScreenBrightness.instance.resetApplicationScreenBrightness();
  } catch (e) {
    debugPrint(e.toString());
    throw 'Failed to reset application brightness';
  }
}
```
#### System brightness changed stream
```dart
@override
Widget build(BuildContext context) {
  return StreamBuilder<double>(
    stream:
    ScreenBrightness.instance.onSystemScreenBrightnessChanged,
    builder: (context, snapshot) {
      double changedSystemBrightness = systemBrightness;
      if (snapshot.hasData) {
        changedSystemBrightness = snapshot.data!;
      }
      
      return Text('system brightness $changedSystemBrightness');
    },
  );
}
```
#### Application brightness changed stream
```dart
@override
Widget build(BuildContext context) {
  return StreamBuilder<double>(
    stream:
    ScreenBrightness.instance.onApplicationScreenBrightnessChanged,
    builder: (context, snapshot) {
      double changedApplicationBrightness = applicationBrightness;
      if (snapshot.hasData) {
        changedApplicationBrightness = snapshot.data!;
      }

      return Text('application brightness $changedApplicationBrightness');
    },
  );
}
```
#### Has application brightness changed
```dart
@override
Widget build(BuildContext context) {
  return FutureBuilder<bool>(
    future: ScreenBrightness.instance.hasApplicationScreenBrightnessChanged,
    builder: (context, snapshot) {
      return Text(
          'Application brightness has changed via plugin: ${snapshot.data}');
    },
  );
}
```

#### Auto reset
```dart
bool isAutoReset = true;

Future<void> getIsAutoResetSetting() async {
  final isAutoReset = await ScreenBrightness.instance.isAutoReset;
  setState(() {
    this.isAutoReset = isAutoReset;
  });
}

@override
Widget build(BuildContext context) {
  return Switch(
    value: isAutoReset,
    onChanged: (value) async {
      await ScreenBrightness.instance.setAutoReset(value);
      await getIsAutoResetSetting();
    },
  );
}
```

#### Can change system brightness
```dart

bool canChangeSystemBrightness = true;

Future<void> getCanChangeSystemBrightness() async {
  final canChangeSystemBrightness = await ScreenBrightness.instance.canChangeSystemBrightness;
  setState(() {
    this.canChangeSystemBrightness = canChangeSystemBrightness;
  });
}

@override
Widget build(BuildContext context) {
  return Switch(
    value: canChangeSystemBrightness,
    onChanged: (value) {},
  );
}
```

### Usage

* You may also use this plugin with [wakelock](https://pub.dev/packages/wakelock) to prevent screen sleep

## Maintainer

[Jack Liu](https://github.com/aaassseee)