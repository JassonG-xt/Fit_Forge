import Testing
@testable import FitForge

// MARK: - PlanEngine 测试

struct PlanEngineTests {

    @Test("训练分化模式选择")
    func testDetermineSplit() {
        #expect(PlanEngine.determineSplit(frequency: 1) == .fullBody)
        #expect(PlanEngine.determineSplit(frequency: 2) == .fullBody)
        #expect(PlanEngine.determineSplit(frequency: 3) == .pushPullLegs)
        #expect(PlanEngine.determineSplit(frequency: 4) == .upperLower)
        #expect(PlanEngine.determineSplit(frequency: 5) == .pushPullLegs)
        #expect(PlanEngine.determineSplit(frequency: 6) == .pushPullLegs)
    }

    @Test("每周日程构建 - 全身训练")
    func testFullBodySchedule() {
        let schedule = PlanEngine.buildWeeklySchedule(split: .fullBody, frequency: 2)
        #expect(schedule.count == 7)
        let trainingDays = schedule.filter { $0 != .rest }
        #expect(trainingDays.count == 2)
        #expect(trainingDays.allSatisfy { $0 == .fullBody })
    }

    @Test("每周日程构建 - 推拉腿 3天")
    func testPPLSchedule3Days() {
        let schedule = PlanEngine.buildWeeklySchedule(split: .pushPullLegs, frequency: 3)
        #expect(schedule.count == 7)
        let types = schedule.filter { $0 != .rest }
        #expect(types.count == 3)
        #expect(types.contains(.push))
        #expect(types.contains(.pull))
        #expect(types.contains(.legs))
    }

    @Test("每周日程构建 - 上下肢 4天")
    func testUpperLowerSchedule() {
        let schedule = PlanEngine.buildWeeklySchedule(split: .upperLower, frequency: 4)
        let types = schedule.filter { $0 != .rest }
        #expect(types.count == 4)
        #expect(types.filter({ $0 == .upper }).count == 2)
        #expect(types.filter({ $0 == .lower }).count == 2)
    }

    @Test("训练参数 - 增肌")
    func testBuildMuscleParams() {
        let params = PlanEngine.trainingParameters(for: .buildMuscle, level: .intermediate)
        #expect(params.sets == 4)
        #expect(params.reps == 10)
        #expect(params.restSeconds == 75)
        #expect(params.compoundFirst == true)
    }

    @Test("训练参数 - 减脂")
    func testLoseFatParams() {
        let params = PlanEngine.trainingParameters(for: .loseFat, level: .beginner)
        #expect(params.sets == 3)
        #expect(params.reps == 14)
        #expect(params.restSeconds == 40)
    }

    @Test("热身推荐非空")
    func testWarmupRecommendations() {
        let warmup = PlanEngine.warmupRecommendation(for: .push)
        #expect(!warmup.isEmpty)
        #expect(warmup.count >= 4)
    }

    @Test("拉伸推荐非空")
    func testCooldownRecommendations() {
        let cooldown = PlanEngine.cooldownRecommendation(for: .legs)
        #expect(!cooldown.isEmpty)
    }
}

// MARK: - NutritionEngine 测试

struct NutritionEngineTests {

    @Test("BMR 计算 - 男性")
    func testBMRMale() {
        let profile = UserProfile(
            heightCm: 175,
            weightKg: 75,
            age: 25,
            gender: .male,
            goal: .buildMuscle,
            weeklyFrequency: 4
        )
        // Mifflin: 10*75 + 6.25*175 - 5*25 + 5 = 750 + 1093.75 - 125 + 5 = 1723.75
        let bmr = profile.bmr
        #expect(bmr > 1720 && bmr < 1730)
    }

    @Test("BMR 计算 - 女性")
    func testBMRFemale() {
        let profile = UserProfile(
            heightCm: 163,
            weightKg: 55,
            age: 28,
            gender: .female,
            goal: .loseFat,
            weeklyFrequency: 3
        )
        // Mifflin: 10*55 + 6.25*163 - 5*28 - 161 = 550 + 1018.75 - 140 - 161 = 1267.75
        let bmr = profile.bmr
        #expect(bmr > 1265 && bmr < 1270)
    }

    @Test("TDEE 计算")
    func testTDEE() {
        let profile = UserProfile(
            heightCm: 175,
            weightKg: 75,
            age: 25,
            gender: .male,
            weeklyFrequency: 4
        )
        // TDEE = BMR * 1.55 (3-4次/周)
        let tdee = profile.tdee
        let expectedTDEE = profile.bmr * 1.55
        #expect(abs(tdee - expectedTDEE) < 1.0)
    }

    @Test("增肌热量盈余")
    func testBuildMuscleMacros() {
        let profile = UserProfile(
            heightCm: 175,
            weightKg: 75,
            age: 25,
            gender: .male,
            goal: .buildMuscle,
            weeklyFrequency: 4
        )
        let macros = NutritionEngine.calculateMacros(for: profile)
        // 增肌: TDEE + 300
        let expected = Int(profile.tdee + 300)
        #expect(macros.calories == expected)
        // 蛋白质: 2.0g/kg = 150g
        #expect(macros.proteinGrams == 150)
    }

    @Test("减脂热量不低于安全下限")
    func testLoseFatFloor() {
        let profile = UserProfile(
            heightCm: 155,
            weightKg: 45,
            age: 22,
            gender: .female,
            goal: .loseFat,
            weeklyFrequency: 2
        )
        let macros = NutritionEngine.calculateMacros(for: profile)
        let floor = profile.bmr * 1.1
        #expect(Double(macros.calories) >= floor)
    }

    @Test("饮食计划生成非空")
    func testMealPlanGeneration() {
        let profile = UserProfile(
            heightCm: 170,
            weightKg: 70,
            age: 30,
            gender: .male,
            goal: .buildMuscle
        )
        let macros = NutritionEngine.calculateMacros(for: profile)
        let meals = NutritionEngine.generateMealPlan(macros: macros, goal: .buildMuscle)
        #expect(!meals.isEmpty)
        #expect(meals.count >= 4) // 增肌: 早午晚 + 加餐
    }

    @Test("饮水量建议")
    func testWaterIntake() {
        let water = NutritionEngine.dailyWaterIntake(weightKg: 70, workoutDays: 4)
        // 70 * 35 + 500 = 2950
        #expect(water == 2950)
    }
}
