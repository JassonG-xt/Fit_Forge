// FitForge 所有枚举定义

// ──────────── 性别 ────────────
enum Gender {
  male,
  female,
  other;

  String get displayName {
    switch (this) {
      case Gender.male:
        return '男';
      case Gender.female:
        return '女';
      case Gender.other:
        return '其他';
    }
  }
}

// ──────────── 健身目标 ────────────
enum FitnessGoal {
  buildMuscle,
  loseFat,
  maintain,
  endurance;

  String get displayName {
    switch (this) {
      case FitnessGoal.buildMuscle:
        return '增肌';
      case FitnessGoal.loseFat:
        return '减脂';
      case FitnessGoal.maintain:
        return '维持体型';
      case FitnessGoal.endurance:
        return '提升耐力';
    }
  }

  String get icon {
    switch (this) {
      case FitnessGoal.buildMuscle:
        return '💪';
      case FitnessGoal.loseFat:
        return '🔥';
      case FitnessGoal.maintain:
        return '⚖️';
      case FitnessGoal.endurance:
        return '🏃';
    }
  }
}

// ──────────── 经验等级 ────────────
enum ExperienceLevel {
  beginner,
  intermediate,
  advanced;

  String get displayName {
    switch (this) {
      case ExperienceLevel.beginner:
        return '新手';
      case ExperienceLevel.intermediate:
        return '中级';
      case ExperienceLevel.advanced:
        return '高级';
    }
  }

  String get description {
    switch (this) {
      case ExperienceLevel.beginner:
        return '训练不到 6 个月';
      case ExperienceLevel.intermediate:
        return '训练 6 个月到 2 年';
      case ExperienceLevel.advanced:
        return '训练 2 年以上';
    }
  }
}

// ──────────── 身体部位 ────────────
enum BodyPart {
  chest,
  back,
  shoulders,
  biceps,
  triceps,
  legs,
  glutes,
  abs,
  calves,
  forearms,
  fullBody,
  cardio;

  String get displayName {
    switch (this) {
      case BodyPart.chest:
        return '胸部';
      case BodyPart.back:
        return '背部';
      case BodyPart.shoulders:
        return '肩部';
      case BodyPart.biceps:
        return '肱二头肌';
      case BodyPart.triceps:
        return '肱三头肌';
      case BodyPart.legs:
        return '腿部';
      case BodyPart.glutes:
        return '臀部';
      case BodyPart.abs:
        return '腹部';
      case BodyPart.calves:
        return '小腿';
      case BodyPart.forearms:
        return '前臂';
      case BodyPart.fullBody:
        return '全身';
      case BodyPart.cardio:
        return '有氧';
    }
  }
}

// ──────────── 器械类型 ────────────
enum Equipment {
  barbell,
  dumbbell,
  machine,
  cable,
  bodyweight,
  kettlebell,
  resistanceBand,
  smithMachine,
  pullUpBar,
  bench,
  ezBar,
  treadmill,
  bike,
  rowingMachine;

  String get displayName {
    switch (this) {
      case Equipment.barbell:
        return '杠铃';
      case Equipment.dumbbell:
        return '哑铃';
      case Equipment.machine:
        return '固定器械';
      case Equipment.cable:
        return '绳索';
      case Equipment.bodyweight:
        return '自重';
      case Equipment.kettlebell:
        return '壶铃';
      case Equipment.resistanceBand:
        return '弹力带';
      case Equipment.smithMachine:
        return '史密斯机';
      case Equipment.pullUpBar:
        return '引体向上杆';
      case Equipment.bench:
        return '卧推凳';
      case Equipment.ezBar:
        return '曲杆';
      case Equipment.treadmill:
        return '跑步机';
      case Equipment.bike:
        return '动感单车';
      case Equipment.rowingMachine:
        return '划船机';
    }
  }
}

// ──────────── 训练分化模式 ────────────
enum TrainingSplit {
  fullBody,
  upperLower,
  pushPullLegs,
  custom;

  String get displayName {
    switch (this) {
      case TrainingSplit.fullBody:
        return '全身训练';
      case TrainingSplit.upperLower:
        return '上下肢分化';
      case TrainingSplit.pushPullLegs:
        return '推拉腿';
      case TrainingSplit.custom:
        return '自定义';
    }
  }
}

// ──────────── 训练日类型 ────────────
enum WorkoutDayType {
  push,
  pull,
  legs,
  upper,
  lower,
  fullBody,
  rest,
  cardio;

  String get displayName {
    switch (this) {
      case WorkoutDayType.push:
        return '推 (胸/肩/三头)';
      case WorkoutDayType.pull:
        return '拉 (背/二头)';
      case WorkoutDayType.legs:
        return '腿 (腿/臀)';
      case WorkoutDayType.upper:
        return '上肢';
      case WorkoutDayType.lower:
        return '下肢';
      case WorkoutDayType.fullBody:
        return '全身';
      case WorkoutDayType.rest:
        return '休息日';
      case WorkoutDayType.cardio:
        return '有氧';
    }
  }

  List<BodyPart> get targetBodyParts {
    switch (this) {
      case WorkoutDayType.push:
        return [BodyPart.chest, BodyPart.shoulders, BodyPart.triceps];
      case WorkoutDayType.pull:
        return [BodyPart.back, BodyPart.biceps, BodyPart.forearms];
      case WorkoutDayType.legs:
        return [BodyPart.legs, BodyPart.glutes, BodyPart.calves];
      case WorkoutDayType.upper:
        return [
          BodyPart.chest,
          BodyPart.back,
          BodyPart.shoulders,
          BodyPart.biceps,
          BodyPart.triceps,
        ];
      case WorkoutDayType.lower:
        return [BodyPart.legs, BodyPart.glutes, BodyPart.calves];
      case WorkoutDayType.fullBody:
        return [
          BodyPart.chest,
          BodyPart.back,
          BodyPart.shoulders,
          BodyPart.legs,
          BodyPart.abs,
        ];
      case WorkoutDayType.rest:
        return [];
      case WorkoutDayType.cardio:
        return [BodyPart.cardio];
    }
  }
}

// ──────────── 成就类型 ────────────
enum AchievementType {
  streak,
  totalWorkouts,
  personalRecord,
  bodyPartMastery,
  nutritionStreak;

  String get displayName {
    switch (this) {
      case AchievementType.streak:
        return '连续打卡';
      case AchievementType.totalWorkouts:
        return '训练达人';
      case AchievementType.personalRecord:
        return '突破自我';
      case AchievementType.bodyPartMastery:
        return '专注训练';
      case AchievementType.nutritionStreak:
        return '饮食管理';
    }
  }
}
