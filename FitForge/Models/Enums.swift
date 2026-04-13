import Foundation

// MARK: - 性别
enum Gender: String, Codable, CaseIterable, Identifiable {
    case male = "male"
    case female = "female"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: return "男"
        case .female: return "女"
        case .other: return "其他"
        }
    }
}

// MARK: - 健身目标
enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case buildMuscle = "buildMuscle"
    case loseFat = "loseFat"
    case maintain = "maintain"
    case endurance = "endurance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .buildMuscle: return "增肌"
        case .loseFat: return "减脂"
        case .maintain: return "维持体型"
        case .endurance: return "提升耐力"
        }
    }

    var icon: String {
        switch self {
        case .buildMuscle: return "figure.strengthtraining.traditional"
        case .loseFat: return "flame.fill"
        case .maintain: return "figure.walk"
        case .endurance: return "figure.run"
        }
    }
}

// MARK: - 经验等级
enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "新手"
        case .intermediate: return "中级"
        case .advanced: return "高级"
        }
    }

    var description: String {
        switch self {
        case .beginner: return "训练不到 6 个月"
        case .intermediate: return "训练 6 个月到 2 年"
        case .advanced: return "训练 2 年以上"
        }
    }
}

// MARK: - 身体部位
enum BodyPart: String, Codable, CaseIterable, Identifiable {
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case biceps = "biceps"
    case triceps = "triceps"
    case legs = "legs"
    case glutes = "glutes"
    case abs = "abs"
    case calves = "calves"
    case forearms = "forearms"
    case fullBody = "fullBody"
    case cardio = "cardio"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "胸部"
        case .back: return "背部"
        case .shoulders: return "肩部"
        case .biceps: return "肱二头肌"
        case .triceps: return "肱三头肌"
        case .legs: return "腿部"
        case .glutes: return "臀部"
        case .abs: return "腹部"
        case .calves: return "小腿"
        case .forearms: return "前臂"
        case .fullBody: return "全身"
        case .cardio: return "有氧"
        }
    }

    var icon: String {
        switch self {
        case .chest: return "figure.strengthtraining.functional"
        case .back: return "figure.rowing"
        case .shoulders: return "figure.boxing"
        case .biceps: return "figure.strengthtraining.traditional"
        case .triceps: return "figure.strengthtraining.traditional"
        case .legs: return "figure.walk"
        case .glutes: return "figure.step.training"
        case .abs: return "figure.core.training"
        case .calves: return "figure.walk"
        case .forearms: return "hand.raised.fill"
        case .fullBody: return "figure.mixed.cardio"
        case .cardio: return "figure.run"
        }
    }
}

// MARK: - 肌肉群
enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case pectoralMajor = "pectoralMajor"       // 胸大肌
    case anteriorDeltoid = "anteriorDeltoid"     // 三角肌前束
    case lateralDeltoid = "lateralDeltoid"       // 三角肌中束
    case posteriorDeltoid = "posteriorDeltoid"   // 三角肌后束
    case latissimusDorsi = "latissimusDorsi"     // 背阔肌
    case traps = "traps"                         // 斜方肌
    case rhomboids = "rhomboids"                 // 菱形肌
    case bicepsBrachii = "bicepsBrachii"         // 肱二头肌
    case tricepsBrachii = "tricepsBrachii"       // 肱三头肌
    case quadriceps = "quadriceps"               // 股四头肌
    case hamstrings = "hamstrings"               // 腘绳肌
    case gluteusMaximus = "gluteusMaximus"       // 臀大肌
    case gastrocnemius = "gastrocnemius"          // 腓肠肌
    case rectusAbdominis = "rectusAbdominis"      // 腹直肌
    case obliques = "obliques"                   // 腹斜肌
    case erectorSpinae = "erectorSpinae"         // 竖脊肌
    case forearmFlexors = "forearmFlexors"        // 前臂屈肌

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pectoralMajor: return "胸大肌"
        case .anteriorDeltoid: return "三角肌前束"
        case .lateralDeltoid: return "三角肌中束"
        case .posteriorDeltoid: return "三角肌后束"
        case .latissimusDorsi: return "背阔肌"
        case .traps: return "斜方肌"
        case .rhomboids: return "菱形肌"
        case .bicepsBrachii: return "肱二头肌"
        case .tricepsBrachii: return "肱三头肌"
        case .quadriceps: return "股四头肌"
        case .hamstrings: return "腘绳肌"
        case .gluteusMaximus: return "臀大肌"
        case .gastrocnemius: return "腓肠肌"
        case .rectusAbdominis: return "腹直肌"
        case .obliques: return "腹斜肌"
        case .erectorSpinae: return "竖脊肌"
        case .forearmFlexors: return "前臂屈肌"
        }
    }
}

// MARK: - 器械类型
enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell = "barbell"
    case dumbbell = "dumbbell"
    case machine = "machine"
    case cable = "cable"
    case bodyweight = "bodyweight"
    case kettlebell = "kettlebell"
    case resistanceBand = "resistanceBand"
    case smithMachine = "smithMachine"
    case pullUpBar = "pullUpBar"
    case bench = "bench"
    case ezBar = "ezBar"
    case treadmill = "treadmill"
    case bike = "bike"
    case rowingMachine = "rowingMachine"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: return "杠铃"
        case .dumbbell: return "哑铃"
        case .machine: return "固定器械"
        case .cable: return "绳索"
        case .bodyweight: return "自重"
        case .kettlebell: return "壶铃"
        case .resistanceBand: return "弹力带"
        case .smithMachine: return "史密斯机"
        case .pullUpBar: return "引体向上杆"
        case .bench: return "卧推凳"
        case .ezBar: return "曲杆"
        case .treadmill: return "跑步机"
        case .bike: return "动感单车"
        case .rowingMachine: return "划船机"
        }
    }

    var icon: String {
        switch self {
        case .barbell: return "dumbbell.fill"
        case .dumbbell: return "dumbbell.fill"
        case .machine: return "gearshape.fill"
        case .cable: return "lines.measurement.horizontal"
        case .bodyweight: return "figure.stand"
        case .kettlebell: return "scalemass.fill"
        case .resistanceBand: return "lasso"
        case .smithMachine: return "square.grid.3x3.fill"
        case .pullUpBar: return "rectangle.topthird.inset.filled"
        case .bench: return "bed.double.fill"
        case .ezBar: return "dumbbell.fill"
        case .treadmill: return "figure.run"
        case .bike: return "bicycle"
        case .rowingMachine: return "figure.rowing"
        }
    }
}

// MARK: - 训练分化模式
enum TrainingSplit: String, Codable, CaseIterable, Identifiable {
    case fullBody = "fullBody"
    case upperLower = "upperLower"
    case pushPullLegs = "pushPullLegs"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullBody: return "全身训练"
        case .upperLower: return "上下肢分化"
        case .pushPullLegs: return "推拉腿"
        case .custom: return "自定义"
        }
    }
}

// MARK: - 训练日类型
enum WorkoutDayType: String, Codable, CaseIterable, Identifiable {
    case push = "push"
    case pull = "pull"
    case legs = "legs"
    case upper = "upper"
    case lower = "lower"
    case fullBody = "fullBody"
    case rest = "rest"
    case cardio = "cardio"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push: return "推 (胸/肩/三头)"
        case .pull: return "拉 (背/二头)"
        case .legs: return "腿 (腿/臀)"
        case .upper: return "上肢"
        case .lower: return "下肢"
        case .fullBody: return "全身"
        case .rest: return "休息日"
        case .cardio: return "有氧"
        }
    }

    var targetBodyParts: [BodyPart] {
        switch self {
        case .push: return [.chest, .shoulders, .triceps]
        case .pull: return [.back, .biceps, .forearms]
        case .legs: return [.legs, .glutes, .calves]
        case .upper: return [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: return [.legs, .glutes, .calves]
        case .fullBody: return [.chest, .back, .shoulders, .legs, .abs]
        case .rest: return []
        case .cardio: return [.cardio]
        }
    }
}

// MARK: - 音乐类型
enum MusicGenre: String, Codable, CaseIterable, Identifiable {
    case hiphop = "hiphop"
    case electronic = "electronic"
    case rock = "rock"
    case pop = "pop"
    case metal = "metal"
    case motivation = "motivation"
    case lofi = "lofi"
    case latin = "latin"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hiphop: return "嘻哈"
        case .electronic: return "电子"
        case .rock: return "摇滚"
        case .pop: return "流行"
        case .metal: return "金属"
        case .motivation: return "激励"
        case .lofi: return "Lo-Fi"
        case .latin: return "拉丁"
        }
    }

    var icon: String {
        switch self {
        case .hiphop: return "headphones"
        case .electronic: return "waveform"
        case .rock: return "guitars.fill"
        case .pop: return "music.note"
        case .metal: return "bolt.fill"
        case .motivation: return "flame.fill"
        case .lofi: return "cloud.fill"
        case .latin: return "music.mic"
        }
    }

    var searchKeywords: [String] {
        switch self {
        case .hiphop: return ["hip hop workout", "rap gym", "嘻哈健身"]
        case .electronic: return ["EDM workout", "electronic gym", "电子音乐健身"]
        case .rock: return ["rock workout", "摇滚健身"]
        case .pop: return ["pop workout", "流行健身音乐"]
        case .metal: return ["metal workout", "metalcore gym"]
        case .motivation: return ["motivation workout", "激励训练音乐"]
        case .lofi: return ["lofi workout", "chill gym"]
        case .latin: return ["latin workout", "reggaeton gym"]
        }
    }
}

// MARK: - 成就类型
enum AchievementType: String, Codable, CaseIterable, Identifiable {
    case streak = "streak"              // 连续打卡
    case totalWorkouts = "totalWorkouts" // 累计训练次数
    case personalRecord = "personalRecord" // 个人记录突破
    case bodyPartMastery = "bodyPartMastery" // 部位训练达人
    case nutritionStreak = "nutritionStreak" // 饮食打卡

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .streak: return "连续打卡"
        case .totalWorkouts: return "训练达人"
        case .personalRecord: return "突破自我"
        case .bodyPartMastery: return "专注训练"
        case .nutritionStreak: return "饮食管理"
        }
    }
}
