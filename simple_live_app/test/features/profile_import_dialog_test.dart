import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/sync/profile_backup/profile_import_dialog.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';

ProfileInspection _inspection(
  Map<ProfileCategory, ProfileCategoryInfo> categories,
) {
  return ProfileInspection(
    kind: ProfilePackageKind.profile,
    payload: const {},
    appVersion: "1.2.3",
    categories: categories,
  );
}

const _info = ProfileCategoryInfo(count: 1, detail: "1 项");

Future<ProfileImportDecision?> _pumpDialog(
  WidgetTester tester,
  ProfileInspection inspection, {
  Set<ProfileCategory>? preselected,
}) async {
  ProfileImportDecision? result;
  var completed = false;
  await tester.pumpWidget(
    GetMaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showDialog<ProfileImportDecision>(
                  context: context,
                  builder: (_) => ProfileImportDialog(
                    inspection: inspection,
                    preselected: preselected,
                  ),
                );
                completed = true;
              },
              child: const Text("open"),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
  addTearDown(() => expect(completed || result == null, isTrue));
  return result;
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('只列出包内识别到的分类', (tester) async {
    await _pumpDialog(
      tester,
      _inspection({
        ProfileCategory.settings: _info,
        ProfileCategory.follows: const ProfileCategoryInfo(
          count: 3,
          detail: "2 个关注，1 个标签",
        ),
      }),
    );

    expect(find.text(ProfileCategory.settings.title), findsOneWidget);
    expect(find.text(ProfileCategory.follows.title), findsOneWidget);
    // 包里没有的分类不出现，用户无需对不存在的内容做选择。
    expect(find.text(ProfileCategory.histories.title), findsNothing);
    expect(find.text(ProfileCategory.accounts.title), findsNothing);
    expect(find.textContaining("2 个关注，1 个标签"), findsOneWidget);
  });

  testWidgets('默认勾选除账号外的全部分类，覆盖开关默认关闭', (tester) async {
    await _pumpDialog(
      tester,
      _inspection({
        ProfileCategory.settings: _info,
        ProfileCategory.accounts: _info,
      }),
    );

    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(boxes.length, 2);
    expect(boxes.first.value, isTrue); // 设置
    expect(boxes.last.value, isFalse); // 账号登录信息
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets('预勾选与包内内容求交集', (tester) async {
    await _pumpDialog(
      tester,
      _inspection({
        ProfileCategory.settings: _info,
        ProfileCategory.follows: _info,
      }),
      // 关注页只想导入关注数据，且历史根本不在包内。
      preselected: {ProfileCategory.follows, ProfileCategory.histories},
    );

    final tiles = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(tiles.length, 2);
    expect(tiles[0].value, isFalse); // 设置未预选
    expect(tiles[1].value, isTrue); // 关注已预选
    expect(find.text(ProfileCategory.histories.title), findsNothing);
  });

  testWidgets('确认导入回传勾选结果与覆盖开关', (tester) async {
    ProfileImportDecision? decision;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  decision = await showDialog<ProfileImportDecision>(
                    context: context,
                    builder: (_) => ProfileImportDialog(
                      inspection: _inspection({
                        ProfileCategory.settings: _info,
                        ProfileCategory.follows: _info,
                      }),
                    ),
                  );
                },
                child: const Text("open"),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();

    // 取消勾选设置，只保留关注，并打开覆盖。
    await tester.tap(find.text(ProfileCategory.settings.title));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text("确认导入"));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.categories, {ProfileCategory.follows});
    expect(decision!.overwrite, isTrue);
    expect(decision!.options.follows, isTrue);
    expect(decision!.options.settings, isFalse);
  });

  testWidgets('取消返回 null，全部取消勾选时无法确认', (tester) async {
    ProfileImportDecision? decision;
    var returned = false;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  decision = await showDialog<ProfileImportDecision>(
                    context: context,
                    builder: (_) => ProfileImportDialog(
                      inspection: _inspection({
                        ProfileCategory.settings: _info,
                      }),
                    ),
                  );
                  returned = true;
                },
                child: const Text("open"),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();

    // 取消唯一勾选后确认按钮应禁用。
    await tester.tap(find.text(ProfileCategory.settings.title));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text("确认导入"),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text("取消"));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(decision, isNull);
  });
}
