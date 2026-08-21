import 'package:hive/hive.dart';
import 'package:krag_app/constants/index.dart' as constants;

part 'note_models.g.dart';

@HiveType(typeId: 0)
class Tag extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String color;

  Tag({required this.name, required this.color});

  factory Tag.create(String name) {
    return Tag(name: name, color: constants.AppConstants.defaultTagColor);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'color': color,
      };

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      name: json['name'] as String,
      color: json['color'] as String,
    );
  }
}
