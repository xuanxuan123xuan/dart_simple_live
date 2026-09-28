import 'dart:convert';

class LiveCategory {
  final String name;
  final String id;
  final String? pic;
  final List<LiveSubCategory> children;
  LiveCategory({
    required this.id,
    required this.name,
    required this.children,
    this.pic,
  });

  factory LiveCategory.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    if (json['id'] == null || json['name'] == null || rawChildren is! List) {
      throw const FormatException('Invalid live category snapshot');
    }
    return LiveCategory(
      id: json['id'].toString(),
      name: json['name'].toString(),
      pic: json['pic']?.toString(),
      children: rawChildren
          .map((item) => LiveSubCategory.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'pic': pic,
        'children': children.map((item) => item.toJson()).toList(),
      };

  @override
  String toString() {
    return json.encode(toJson());
  }
}

class LiveSubCategory {
  final String name;
  final String? pic;
  final String id;
  final String parentId;
  /// 子分类，支持多级嵌套（抖音游戏分区存在三级）。
  final List<LiveSubCategory> children;

  LiveSubCategory({
    required this.id,
    required this.name,
    required this.parentId,
    this.pic,
    this.children = const <LiveSubCategory>[],
  });

  factory LiveSubCategory.fromJson(Map<String, dynamic> json) {
    if (json['id'] == null ||
        json['name'] == null ||
        json['parentId'] == null) {
      throw const FormatException('Invalid live subcategory snapshot');
    }
    return LiveSubCategory(
      id: json['id'].toString(),
      name: json['name'].toString(),
      parentId: json['parentId'].toString(),
      pic: json['pic']?.toString(),
      children: parseChildren(json['children']),
    );
  }

  /// 解析嵌套子分类；单个异常节点不会让整份快照解析失败。
  static List<LiveSubCategory> parseChildren(dynamic value) {
    if (value is! List) {
      return const <LiveSubCategory>[];
    }
    final result = <LiveSubCategory>[];
    for (final item in value) {
      if (item is! Map) {
        continue;
      }
      try {
        result.add(
          LiveSubCategory.fromJson(Map<String, dynamic>.from(item)),
        );
      } on FormatException {
        // 可选字段异常时跳过该节点，保留其余分类。
      }
    }
    return List<LiveSubCategory>.unmodifiable(result);
  }

  bool get hasChildren => children.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'parentId': parentId,
        'pic': pic,
        'children': children.map((item) => item.toJson()).toList(),
      };

  @override
  String toString() {
    return json.encode(toJson());
  }
}
