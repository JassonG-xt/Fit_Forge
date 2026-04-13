import Foundation
import SwiftData

/// 训练计划生成引擎
/// 根据用户画像（身高体重、目标、频率、器械等）动态生成个性化训练计划
struct PlanEngine {

    // MARK: - 主入口

    /// 为用户生成一周训练计划
    static func generatePlan(for profile: UserProfile, exercises: [Exercise]) -> WorkoutPlan {
        let split = determineSplit(frequency: profile.weeklyFrequency)
        let schedule = buildWeeklySchedule(split: split, frequency: profile.weeklyFrequency)
        let params = trainingParameters(for: profile.goal, level: profile.experienceLevel)

        var days: [WorkoutDay] = []

        for (index, dayType) in schedule.enumerated() {
            let dayOfWeek = index + 1 // 1=周一
            if dayType == .rest {
                days.append(WorkoutDay(dayOfWeek: dayOfWeek, dayType: .rest, sortOrder: index))
                continue
            }

            let targetParts = dayType.targetBodyParts
            let selectedExercises = selectExercises(
                for: targetParts,
                from: exercises,
                availableEquipment: profile.availableEquipment,
                level: profile.experienceLevel,
                params: params
            )

            let planned = selectedExercises.enumerated().map { i, exercise in
                PlannedExercise(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    targetSets: params.sets,
                    targetReps: params.reps,
                    restSeconds: params.restSeconds,
                    sortOrder: i
                )
            }

            let day = WorkoutDay(dayOfWeek: dayOfWeek, dayType: dayType, sortOrder: index, plannedExercises: planned)
            days.append(day)
        }

        let planName = "\(profile.goal.displayName) - \(split.displayName)"
        return WorkoutPlan(
            name: planName,
            goal: profile.goal,
            split: split,
            weeklyFrequency: profile.weeklyFrequency,
            days: days
        )
    }

    // MARK: - Step 1: 确定训练分化模式

    /// 根据每周训练频率选择最优分化模式
    static func determineSplit(frequency: Int) -> TrainingSplit {
        switch frequency {
        case 1...2:
            return .fullBody
        case 3:
            return .pushPullLegs
        case 4:
            return .upperLower
        case 5...7:
            return .pushPullLegs
        default:
            return .fullBody
        }
    }

    // MARK: - Step 2: 构建一周日程

    /// 将 7 天分配为训练日和休息日
    static func buildWeeklySchedule(split: TrainingSplit, frequency: Int) -> [WorkoutDayType] {
        switch split {
        case .fullBody:
            switch frequency {
            case 1:
                return [.fullBody, .rest, .rest, .rest, .rest, .rest, .rest]
            case 2:
                return [.fullBody, .rest, .rest, .fullBody, .rest, .rest, .rest]
            default:
                return [.fullBody, .rest, .fullBody, .rest, .rest, .rest, .rest]
            }

        case .upperLower:
            // 4天: 上-下-休-上-下-休-休
            return [.upper, .lower, .rest, .upper, .lower, .rest, .rest]

        case .pushPullLegs:
            switch frequency {
            case 3:
                return [.push, .rest, .pull, .rest, .legs, .rest, .rest]
            case 4:
                return [.push, .pull, .rest, .legs, .push, .rest, .rest]
            case 5:
                return [.push, .pull, .legs, .rest, .push, .pull, .rest]
            case 6:
                return [.push, .pull, .legs, .push, .pull, .legs, .rest]
            case 7:
                return [.push, .pull, .legs, .push, .pull, .legs, .cardio]
            default:
                return [.push, .rest, .pull, .rest, .legs, .rest, .rest]
            }

        case .custom:
            return [.fullBody, .rest, .fullBody, .rest, .fullBody, .rest, .rest]
        }
    }

    // MARK: - Step 3: 训练参数

    struct TrainingParams {
        let sets: Int
        let reps: Int
        let restSeconds: Int
        let exercisesPerSession: Int
        let compoundFirst: Bool
    }

    /// 根据训练目标和经验等级确定组数、次数、休息时间
    static func trainingParameters(for goal: FitnessGoal, level: ExperienceLevel) -> TrainingParams {
        let baseExercises: Int
        switch level {
        case .beginner: baseExercises = 4
        case .intermediate: baseExercises = 5
        case .advanced: baseExercises = 6
        }

        switch goal {
        case .buildMuscle:
            return TrainingParams(
                sets: level == .beginner ? 3 : 4,
                reps: 10,
                restSeconds: 75,
                exercisesPerSession: baseExercises,
                compoundFirst: true
            )
        case .loseFat:
            return TrainingParams(
                sets: 3,
                reps: 14,
                restSeconds: 40,
                exercisesPerSession: baseExercises + 1, // 多一个动作用于超级组
                compoundFirst: true
            )
        case .maintain:
            return TrainingParams(
                sets: 3,
                reps: 10,
                restSeconds: 60,
                exercisesPerSession: baseExercises,
                compoundFirst: true
            )
        case .endurance:
            return TrainingParams(
                sets: 3,
                reps: 18,
                restSeconds: 30,
                exercisesPerSession: baseExercises + 1,
                compoundFirst: false
            )
        }
    }

    // MARK: - Step 4: 选择动作

    /// 为指定部位选择合适的动作
    /// 优先选复合动作 → 按可用器械过滤 → 不够时用替代动作
    static func selectExercises(
        for bodyParts: [BodyPart],
        from allExercises: [Exercise],
        availableEquipment: [Equipment],
        level: ExperienceLevel,
        params: TrainingParams
    ) -> [Exercise] {
        var selected: [Exercise] = []
        let maxCount = params.exercisesPerSession

        // 按部位分组可用动作
        for part in bodyParts {
            let candidates = allExercises.filter { exercise in
                exercise.bodyPart == part &&
                availableEquipment.contains(exercise.equipment) &&
                exercise.difficulty.rawValue <= levelThreshold(level)
            }

            if candidates.isEmpty {
                // 尝试寻找替代动作（不同器械但同部位）
                let fallbacks = allExercises.filter { $0.bodyPart == part }
                let fallbackWithAlternative = findAlternative(
                    for: fallbacks,
                    in: allExercises,
                    availableEquipment: availableEquipment
                )
                if let alt = fallbackWithAlternative {
                    selected.append(alt)
                }
                continue
            }

            // 复合动作优先
            var sorted = candidates
            if params.compoundFirst {
                sorted = candidates.sorted { a, b in
                    if a.isCompound != b.isCompound { return a.isCompound }
                    return false
                }
            }

            // 每个部位选 1~2 个动作
            let count = bodyParts.count <= 3 ? 2 : 1
            selected.append(contentsOf: sorted.prefix(count))

            if selected.count >= maxCount { break }
        }

        return Array(selected.prefix(maxCount))
    }

    // MARK: - 辅助

    /// 根据经验等级返回可选动作的难度上限
    private static func levelThreshold(_ level: ExperienceLevel) -> String {
        switch level {
        case .beginner: return ExperienceLevel.beginner.rawValue
        case .intermediate: return ExperienceLevel.intermediate.rawValue
        case .advanced: return ExperienceLevel.advanced.rawValue
        }
    }

    /// 在动作的替代列表中寻找用户有器械可做的替代动作
    private static func findAlternative(
        for exercises: [Exercise],
        in allExercises: [Exercise],
        availableEquipment: [Equipment]
    ) -> Exercise? {
        for exercise in exercises {
            for altId in exercise.alternativeExerciseIds {
                if let alt = allExercises.first(where: { $0.id == altId }),
                   availableEquipment.contains(alt.equipment) {
                    return alt
                }
            }
        }
        // 最后兜底：找同部位的自重动作
        let bodyweight = exercises.first(where: { $0.equipment == .bodyweight })
        return bodyweight
    }

    // MARK: - 热身推荐

    /// 根据今日训练部位推荐热身动作
    static func warmupRecommendation(for dayType: WorkoutDayType) -> [String] {
        let general = ["5 分钟轻度有氧（快走/慢跑/跳绳）", "关节绕环（肩/肘/腕/膝/踝各 10 次）"]

        let specific: [String]
        switch dayType {
        case .push:
            specific = [
                "肩部绕环 15 次",
                "弹力带肩外旋 12 次",
                "空杆卧推 15 次（热身组）",
                "俯卧撑 10 次"
            ]
        case .pull:
            specific = [
                "猫牛伸展 10 次",
                "弹力带拉伸 12 次",
                "悬挂 20 秒",
                "空杆划船 15 次（热身组）"
            ]
        case .legs:
            specific = [
                "深蹲到底 15 次（徒手）",
                "弓步走 10 步",
                "臀桥 15 次",
                "腿后侧拉伸 30 秒"
            ]
        case .upper:
            specific = [
                "肩部绕环 15 次",
                "弹力带拉伸 12 次",
                "俯卧撑 10 次",
                "弹力带面拉 12 次"
            ]
        case .lower:
            specific = [
                "深蹲到底 15 次（徒手）",
                "弓步走 10 步",
                "臀桥 15 次",
                "小腿踮起 20 次"
            ]
        case .fullBody:
            specific = [
                "开合跳 20 次",
                "徒手深蹲 10 次",
                "俯卧撑 10 次",
                "超人式 10 次"
            ]
        case .rest, .cardio:
            specific = []
        }

        return general + specific
    }

    /// 训练后拉伸推荐
    static func cooldownRecommendation(for dayType: WorkoutDayType) -> [String] {
        let general = ["5 分钟慢走放松", "深呼吸 5 次"]

        let specific: [String]
        switch dayType {
        case .push:
            specific = [
                "胸部门框拉伸 30 秒",
                "三头肌过头拉伸 30 秒",
                "肩部横向拉伸 30 秒"
            ]
        case .pull:
            specific = [
                "背阔肌侧拉 30 秒",
                "二头肌墙面拉伸 30 秒",
                "猫牛式放松 10 次"
            ]
        case .legs:
            specific = [
                "股四头肌站立拉伸 30 秒",
                "腘绳肌坐姿拉伸 30 秒",
                "臀部鸽子式 30 秒",
                "小腿墙面拉伸 30 秒"
            ]
        case .upper:
            specific = [
                "胸部门框拉伸 30 秒",
                "背阔肌侧拉 30 秒",
                "肩部拉伸 30 秒"
            ]
        case .lower:
            specific = [
                "股四头肌站立拉伸 30 秒",
                "腘绳肌拉伸 30 秒",
                "臀部拉伸 30 秒"
            ]
        case .fullBody:
            specific = [
                "全身拉伸序列（头到脚）各 20 秒"
            ]
        case .rest, .cardio:
            specific = ["泡沫轴全身放松 5 分钟"]
        }

        return general + specific
    }
}
