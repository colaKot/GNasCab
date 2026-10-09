# -*- coding: utf-8 -*-
"""向 language/*.json 的 video 段插入 PLAY_QUALITY_CONFIG_SAVED。
逐文件：读 -> 定位 SUBTITLE_CONFIG_SAVED 行 -> 按同行缩进/EOL 插入 -> JSON 解析校验 -> 通过才落盘。
"""
import json
import os
import shutil
import sys

LANG_DIR = r"G:\work\nascab\electron_server\language"
BACKUP_DIR = r"G:\work\_patch_backup\2026-10-09_video_quality_badges\language"

TEXTS = {
    "zh-CN": "默认播放画质已保存",
    "en-US": "Default playback quality saved",
    "es-ES": "Calidad de reproducción predeterminada guardada",
    "fr-FR": "Qualité de lecture par défaut enregistrée",
    "de-DE": "Standard-Wiedergabequalität gespeichert",
    "ja-JP": "デフォルトの再生画質を保存しました",
    "pt-BR": "Qualidade de reprodução padrão salva",
    "ru-RU": "Качество воспроизведения по умолчанию сохранено",
    "ar-SA": "تم حفظ جودة التشغيل الافتراضية",
    "ko-KR": "기본 재생 화질이 저장되었습니다",
    "th-TH": "บันทึกคุณภาพการเล่นเริ่มต้นแล้ว",
    "vi-VN": "Đã lưu chất lượng phát mặc định",
    "id-ID": "Kualitas pemutaran default disimpan",
}

KEY = "PLAY_QUALITY_CONFIG_SAVED"
ANCHOR = '"SUBTITLE_CONFIG_SAVED"'

os.makedirs(BACKUP_DIR, exist_ok=True)

changed = []
skipped = []
for locale, text in TEXTS.items():
    path = os.path.join(LANG_DIR, locale + ".json")
    if not os.path.isfile(path):
        print("!! 缺少文件: " + path)
        sys.exit(1)

    with open(path, "rb") as f:
        data = f.read()
    crlf = b"\r\n" in data
    eol = "\r\n" if crlf else "\n"
    src = data.decode("utf-8")

    if '"' + KEY + '"' in src:
        skipped.append(locale)
        continue

    lines = src.split(eol)
    hit = -1
    for i, line in enumerate(lines):
        if ANCHOR in line:
            hit = i
            break
    if hit < 0:
        print("!! 未找到锚点 %s -> %s" % (ANCHOR, locale))
        sys.exit(1)

    anchor_line = lines[hit]
    indent = anchor_line[: len(anchor_line) - len(anchor_line.lstrip(" "))]
    new_line = "%s\"%s\": %s," % (
        indent,
        KEY,
        json.dumps(text, ensure_ascii=False),
    )
    lines.insert(hit + 1, new_line)
    out = eol.join(lines)

    # 校验：能解析且新键确实在 messages.video 段下
    parsed = json.loads(out)
    video = (parsed.get("messages") or {}).get("video")
    if not isinstance(video, dict) or KEY not in video:
        print("!! 校验失败（messages.video 段无新键）: " + locale)
        sys.exit(1)

    shutil.copy2(path, os.path.join(BACKUP_DIR, locale + ".json"))
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(out)
    changed.append(locale)

print("已写入: %d -> %s" % (len(changed), ", ".join(changed)))
if skipped:
    print("已存在跳过: %d -> %s" % (len(skipped), ", ".join(skipped)))
