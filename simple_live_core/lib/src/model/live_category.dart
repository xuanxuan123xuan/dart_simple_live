import 'dart:convert';

class LiveCategory {
  final String name;
  final String id;
  final List<LiveSubCategory> children;
  LiveCategory({
    required this.id,
    required this.name,
    required this.children,
  });

  factory LiveCategory.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    if (json['id'] == null || json['name'] == null || rawChildren is! List) {
      throw const FormatException('Invalid live category snapshot');
    }
    return LiveCategory(
      id: json['id'].toString(),
      name: json['name'].toString(),
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
  LiveSubCategory({
    required this.id,
    required this.name,
    required this.parentId,
    this.pic,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'parentId': parentId,
        'pic': pic,
      };

  @override
  String toString() {
    return json.encode(toJson());
  }
}
