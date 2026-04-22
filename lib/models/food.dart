/// 食物数据模型
class Food {
  const Food({
    required this.name,
    required this.category,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.commonPortion,
    required this.portionName,
  });

  factory Food.fromJson(Map<String, dynamic> json) => Food(
    name: json['name'] as String,
    category: json['category'] as String,
    caloriesPer100g: json['caloriesPer100g'] as int,
    proteinPer100g: (json['proteinPer100g'] as num).toDouble(),
    carbsPer100g: (json['carbsPer100g'] as num).toDouble(),
    fatPer100g: (json['fatPer100g'] as num).toDouble(),
    commonPortion: json['commonPortion'] as int,
    portionName: json['portionName'] as String,
  );
  final String name;
  final String category;
  final int caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final int commonPortion; // grams
  final String portionName;

  /// Calories for commonPortion
  int get portionCalories => (caloriesPer100g * commonPortion / 100).round();
  double get portionProtein => proteinPer100g * commonPortion / 100;
  double get portionCarbs => carbsPer100g * commonPortion / 100;
  double get portionFat => fatPer100g * commonPortion / 100;
}
