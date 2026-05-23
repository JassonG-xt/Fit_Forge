from __future__ import annotations

from agents.intent.coach_intent import CoachIntentType, IntentCandidate
from agents.intent.slot_extractor import move_session_pair, raw_target_minutes, target_minutes, weekdays


def route(message: str) -> IntentCandidate:
    text = message.strip()
    lower = text.lower()

    if _has_any(lower, _SAFETY_KEYWORDS):
        return IntentCandidate(CoachIntentType.safety, 0.98, "high-risk health wording")

    pair = move_session_pair(text)
    if pair is not None:
        return IntentCandidate(
            CoachIntentType.moveWorkoutSession,
            0.9,
            "explicit weekday-to-weekday move",
            {"fromDayOfWeek": pair[0], "toDayOfWeek": pair[1]},
        )

    if _is_generate_plan(text):
        return IntentCandidate(CoachIntentType.generatePlan, 0.86, "explicit plan generation wording")

    if _is_messy_schedule(text):
        return IntentCandidate(
            CoachIntentType.rescheduleWeek,
            0.72,
            "weekly schedule wording without scope",
            missing_slots=["scheduleScope"],
        )

    selected_weekdays = weekdays(text)
    if _is_explicit_weekly_schedule(text, selected_weekdays):
        if selected_weekdays:
            available = selected_weekdays
        else:
            available = [1, 2, 3, 4, 5]
        return IntentCandidate(
            CoachIntentType.rescheduleWeek,
            0.88,
            "weekly availability wording with weekdays",
            {"availableWeekdays": available},
        )

    if _is_compress(text):
        target = target_minutes(text)
        raw_target = raw_target_minutes(text)
        missing = [] if target is not None else ["targetDuration"]
        return IntentCandidate(
            CoachIntentType.compressWorkout,
            0.9 if target is not None else 0.72,
            "shorten workout wording with target duration"
            if raw_target is not None
            else "shorten workout wording without target duration",
            {
                **({"targetMinutes": target} if target is not None else {}),
                **({"rawTargetMinutes": raw_target} if raw_target is not None else {}),
            },
            missing,
        )

    if _is_replace(text):
        has_source = _has_specific_exercise(text) or _has_contextual_today_source(text)
        has_equipment = _has_equipment(text)
        return IntentCandidate(
            CoachIntentType.replaceExercise,
            0.86 if has_source and has_equipment else 0.74,
            "replace exercise wording with enough surface details"
            if has_source and has_equipment
            else "replace exercise wording missing concrete details",
            {
                **({"fromExerciseName": "mentioned"} if has_source else {}),
                **({"equipmentConstraint": "mentioned"} if has_equipment else {}),
            },
            [
                *(["sourceExercise"] if not has_source else []),
                *(["availableEquipment"] if not has_equipment else []),
            ],
        )

    if _is_recovery(text):
        return IntentCandidate(CoachIntentType.recoveryAdvice, 0.84, "fatigue or recovery wording")

    if _is_training_feedback(text):
        return IntentCandidate(CoachIntentType.trainingFeedback, 0.82, "training feedback wording")

    if _is_schedule(text):
        return IntentCandidate(
            CoachIntentType.rescheduleWeek,
            0.7,
            "weekly schedule wording without scope",
            missing_slots=["scheduleScope"],
        )

    if _is_nutrition(text):
        return IntentCandidate(CoachIntentType.nutritionAdvice, 0.8, "nutrition wording")

    return IntentCandidate(CoachIntentType.unrelated, 0.4, "no fitness coaching intent matched")


def _is_generate_plan(text: str) -> bool:
    if _is_schedule(text):
        return False
    return _has_any(
        text,
        (
            "生成",
            "做个计划",
            "新计划",
            "新的训练计划",
            "帮我做计划",
            "安排一个适合我的计划",
            "重新开始锻炼",
            "重新开始训练",
            "恢复训练",
            "从哪里开始",
        ),
    )


def _is_compress(text: str) -> bool:
    if _has_any(text, ("这周", "本周")) and "天" in text and "分钟" not in text:
        return False
    return _has_any(
        text,
        (
            "压缩",
            "缩短",
            "短一点",
            "快一点",
            "只有",
            "只能",
            "赶时间",
            "时间不多",
            "时间不够",
            "时间不太够",
            "有点忙",
            "太忙",
            "帮我短一点",
            "快速练",
            "简单练一下",
            "短一点的版本",
            "少练一点",
            "压到",
        ),
    )


def _is_replace(text: str) -> bool:
    return _has_any(
        text,
        (
            "替换",
            "换一个",
            "换个",
            "换成",
            "换成别的",
            "替换掉",
            "做不了",
            "不舒服",
            "动作怎么改",
            "这个动作",
            "调整一下动作",
            "没有这个器械",
            "没有器械",
            "没有杠铃",
            "没有哑铃",
            "没杠铃",
            "没哑铃",
            "器械不方便",
        ),
    )


def _is_schedule(text: str) -> bool:
    return _has_any(text, ("这周", "本周", "周末", "工作日", "训练日", "练不了了", "安排乱了", "训练有点乱"))


def _is_training_feedback(text: str) -> bool:
    return _has_any(
        text,
        (
            "总结",
            "复盘",
            "本周训练",
            "这周训练",
            "一周训练",
            "最近训练",
            "训练安排有没有问题",
            "最近训练安排",
            "练得怎么样",
            "这周训练怎么样",
            "本周训练怎么样",
        ),
    )


def _is_recovery(text: str) -> bool:
    return _has_any(
        text,
        (
            "状态很差",
            "状态一般",
            "降强度",
            "休息还是继续",
            "最近有点累",
            "有点累",
            "练多了",
            "练太密",
            "练得太密",
            "好几天",
            "疲劳",
            "酸痛",
            "腿还酸",
            "累",
            "恢复",
            "连续练",
            "连续训练",
            "还要继续",
            "今天怎么练",
        ),
    )


def _is_messy_schedule(text: str) -> bool:
    return _has_any(
        text,
        (
            "这周训练有点乱",
            "这周安排乱了",
            "这周练不了了",
            "本周训练有点乱",
            "本周安排乱了",
            "本周练不了了",
            "安排乱了",
            "训练有点乱",
            "练不了了",
        ),
    )


def _is_explicit_weekly_schedule(text: str, selected_weekdays: list[int]) -> bool:
    if _has_any(text, ("周末没空", "周末不能", "周末不行", "周末没时间")) and "工作日" in text:
        return True
    if not selected_weekdays:
        return False
    has_weekly_scope = _has_any(text, ("这周", "本周", "训练日", "周末"))
    has_availability = _has_any(
        text,
        ("只能", "只有", "有空", "可以", "安排到", "安排在", "只安排", "重新安排", "重新排"),
    )
    has_training = _has_any(text, ("训练", "练", "安排"))
    return (has_weekly_scope and has_training) or (has_availability and has_training)


def _is_nutrition(text: str) -> bool:
    return _has_any(text, ("吃多了", "晚饭", "晚餐", "午餐", "饮食", "热量", "碳水", "蛋白质", "脂肪", "吃什么", "怎么吃"))


def _has_specific_exercise(text: str) -> bool:
    return _has_any(text, ("深蹲", "卧推", "硬拉", "划船", "引体向上", "推举"))


def _has_contextual_today_source(text: str) -> bool:
    return _has_any(text, ("今天的动作", "今天动作", "今天训练的动作"))


def _has_equipment(text: str) -> bool:
    return _has_any(text, ("杠铃", "哑铃", "器械", "自重", "弹力带", "固定器械", "可用"))


def _has_any(text: str, keys) -> bool:
    return any(k in text for k in keys)


_SAFETY_KEYWORDS = (
    "胸口有点疼",
    "胸口疼",
    "胸痛",
    "头很晕",
    "头晕",
    "眩晕",
    "晕倒",
    "昏厥",
    "呼吸困难",
    "喘不上气",
    "骨折",
    "急性损伤",
    "受伤",
    "剧痛",
    "严重疼",
    "chest pain",
    "dizzy",
    "shortness of breath",
    "severe pain",
)
