from __future__ import annotations

import re


DAY_LOOKUP = {
    "周一": 1,
    "周二": 2,
    "周三": 3,
    "周四": 4,
    "周五": 5,
    "周六": 6,
    "周日": 7,
    "周天": 7,
    "星期一": 1,
    "星期二": 2,
    "星期三": 3,
    "星期四": 4,
    "星期五": 5,
    "星期六": 6,
    "星期日": 7,
    "星期天": 7,
}


def target_minutes(message: str) -> int | None:
    match = re.search(r"(\d+)\s*分钟", message)
    if match:
        value = int(match.group(1))
        if 5 <= value <= 180:
            return value
    if "半小时" in message:
        return 30
    return None


def raw_target_minutes(message: str) -> int | None:
    match = re.search(r"(\d+)\s*分钟", message)
    if match:
        return int(match.group(1))
    if "半小时" in message:
        return 30
    return None


def weekdays(message: str) -> list[int]:
    found = {value for token, value in DAY_LOOKUP.items() if token in message}
    return sorted(found)


def move_session_pair(message: str) -> tuple[int, int] | None:
    move_verbs = ("挪到", "移到", "移动到", "改到", "调到", "换到")
    verb_start = -1
    verb_end = -1
    for verb in move_verbs:
        idx = message.find(verb)
        if idx >= 0 and (verb_start < 0 or idx < verb_start):
            verb_start = idx
            verb_end = idx + len(verb)
    if verb_start < 0:
        return None

    matches = list(re.finditer(r"周[一二三四五六日天]|星期[一二三四五六日天]", message))
    if len(matches) != 2:
        return None

    before = [m for m in matches if m.end() <= verb_start]
    after = [m for m in matches if m.start() >= verb_end]
    if len(before) != 1 or len(after) != 1:
        return None

    src = DAY_LOOKUP.get(before[0].group(0))
    dst = DAY_LOOKUP.get(after[0].group(0))
    if src is None or dst is None or src == dst:
        return None
    return src, dst
