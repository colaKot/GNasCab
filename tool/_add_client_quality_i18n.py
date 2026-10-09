# -*- coding: utf-8 -*-
"""向 flutter_client/lib/core/languages/*.dart 插入本批新增的 11 个键。
分两个锚点插入：
  A 组 video_*  -> 插在 'video_transcode_settings_title' 之前
  B 组 player_info_* -> 插在 'player_quality_original' 所在条目之后
逐文件：读 -> 定位锚点 -> 插入 -> 回读校验（键可被字符串搜到、行数增量正确）-> 落盘。
"""
import io
import os
import shutil
import sys

LANG_DIR = r"G:\work\nascab\flutter_client\lib\core\languages"
BACKUP_DIR = r"G:\work\_patch_backup\2026-10-09_video_quality_badges\client_lang"

# 顺序即插入顺序
VIDEO_KEYS = [
    "video_playback_settings_title",
    "video_default_play_quality",
    "video_default_play_quality_tip",
    "video_play_quality_original",
    "video_badge_dolby_vision",
    "video_badge_dolby_atmos",
    "video_badge_hdr10plus",
    "video_badge_hlg",
]
PLAYER_KEYS = [
    "player_info_bitrate",
    "player_info_source_bitrate",
    "player_info_transcode_bitrate",
]

T = {
    "zh_cn": [
        "播放设置",
        "默认播放画质",
        "每次播放都会按此画质开始；播放中仍可在播放器里临时切换。",
        "原画",
        "杜比视界",
        "杜比全景声",
        "HDR10+",
        "HLG",
        "码率",
        "原始码率",
        "转码码率",
    ],
    "en_us": [
        "Playback Settings",
        "Default playback quality",
        "Every playback starts with this quality; you can still switch temporarily in the player.",
        "Original",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "Bitrate",
        "Source bitrate",
        "Transcoded bitrate",
    ],
    "es_es": [
        "Ajustes de reproducción",
        "Calidad de reproducción predeterminada",
        "Cada reproducción comienza con esta calidad; aún puedes cambiarla temporalmente en el reproductor.",
        "Original",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "Tasa de bits",
        "Tasa de bits original",
        "Tasa de bits transcodificada",
    ],
    "fr_fr": [
        "Réglages de lecture",
        "Qualité de lecture par défaut",
        "Chaque lecture démarre avec cette qualité ; vous pouvez encore la changer temporairement dans le lecteur.",
        "Original",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "Débit",
        "Débit source",
        "Débit transcodé",
    ],
    "de_de": [
        "Wiedergabeeinstellungen",
        "Standard-Wiedergabequalität",
        "Jede Wiedergabe startet mit dieser Qualität; im Player kannst du sie weiterhin temporär wechseln.",
        "Original",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "Bitrate",
        "Quell-Bitrate",
        "Transcodierte Bitrate",
    ],
    "ja_jp": [
        "再生設定",
        "デフォルト再生画質",
        "再生のたびにこの画質で始まります。プレイヤー内で一時的に変更することもできます。",
        "オリジナル",
        "ドルビービジョン",
        "ドルビーアトモス",
        "HDR10+",
        "HLG",
        "ビットレート",
        "元画像のビットレート",
        "トランスコード後ビットレート",
    ],
    "pt_br": [
        "Configurações de reprodução",
        "Qualidade de reprodução padrão",
        "Cada reprodução começa com esta qualidade; ainda é possível mudar temporariamente no player.",
        "Original",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "Taxa de bits",
        "Taxa de bits original",
        "Taxa de bits transcodificada",
    ],
    "ru_ru": [
        "Настройки воспроизведения",
        "Качество воспроизведения по умолчанию",
        "Каждое воспроизведение начинается с этого качества; его всё ещё можно временно изменить в плеере.",
        "Оригинал",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "Битрейт",
        "Исходный битрейт",
        "Битрейт после транскодирования",
    ],
    "ar_ar": [
        "إعدادات التشغيل",
        "جودة التشغيل الافتراضية",
        "يبدأ كل تشغيل بهذه الجودة؛ ولا يزال بإمكانك تغييرها مؤقتًا داخل المشغّل.",
        "الأصلي",
        "دولبي فيجن",
        "دولبي أتموس",
        "HDR10+",
        "HLG",
        "معدل البت",
        "معدل البت الأصلي",
        "معدل البت بعد الترميز",
    ],
    "ko_kr": [
        "재생 설정",
        "기본 재생 화질",
        "모든 재생이 이 화질로 시작하며, 플레이어에서 임시로 변경할 수 있습니다.",
        "원본",
        "돌비 비전",
        "돌비 애트모스",
        "HDR10+",
        "HLG",
        "비트레이트",
        "원본 비트레이트",
        "트랜스코딩 비트레이트",
    ],
    "th_th": [
        "การตั้งค่าการเล่น",
        "คุณภาพการเล่นเริ่มต้น",
        "การเล่นแต่ละครั้งจะเริ่มด้วยคุณภาพนี้ และยังเปลี่ยนชั่วคราวได้ในเครื่องเล่น",
        "ต้นฉบับ",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "อัตราบิต",
        "อัตราบิตต้นฉบับ",
        "อัตราบิตหลังแปลงรหัส",
    ],
    "vi_vn": [
        "Cài đặt phát",
        "Chất lượng phát mặc định",
        "Mỗi lần phát đều bắt đầu ở chất lượng này; bạn vẫn có thể đổi tạm thời trong trình phát.",
        "Gốc",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "Tốc độ bit",
        "Tốc độ bit gốc",
        "Tốc độ bit sau chuyển mã",
    ],
    "id_id": [
        "Pengaturan Pemutaran",
        "Kualitas pemutaran default",
        "Setiap pemutaran dimulai dengan kualitas ini; kamu masih bisa mengubahnya sementara di pemutar.",
        "Original",
        "Dolby Vision",
        "Dolby Atmos",
        "HDR10+",
        "HLG",
        "Kecepatan bit",
        "Kecepatan bit sumber",
        "Kecepatan bit hasil transcode",
    ],
}


def dart_single_quote(value):
    """转义成 Dart 单引号字符串内容。"""
    return value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")


def find_entry_end(lines, key):
    """定位形如  'key': ...  的条目所在行；若值换行则顺延到以逗号结尾的行。返回 0-based 行号。"""
    needle = "'%s':" % key
    for i, line in enumerate(lines):
        if needle in line:
            j = i
            while not lines[j].rstrip().endswith(","):
                j += 1
                if j >= len(lines):
                    raise RuntimeError("条目未以逗号结尾: " + key)
            return j
    raise RuntimeError("未找到锚点键: " + key)


os.makedirs(BACKUP_DIR, exist_ok=True)

for locale, texts in T.items():
    path = os.path.join(LANG_DIR, locale + ".dart")
    if not os.path.isfile(path):
        print("!! 缺少文件: " + path)
        sys.exit(1)

    with io.open(path, "r", encoding="utf-8", newline="") as f:
        src = f.read()
    crlf = "\r\n" in src
    eol = "\r\n" if crlf else "\n"
    lines = src.split(eol)

    if all(("'%s':" % k) in src for k in VIDEO_KEYS) and all(
        ("'%s':" % k) in src for k in PLAYER_KEYS
    ):
        print("跳过（已存在）: " + locale)
        continue

    if len(texts) != len(VIDEO_KEYS) + len(PLAYER_KEYS):
        print("!! 文案数量不匹配: " + locale)
        sys.exit(1)

    # --- B 组：player_info_*，插在 player_quality_original 条目之后 ---
    anchor_b = find_entry_end(lines, "player_quality_original")
    indent_b = lines[anchor_b][: len(lines[anchor_b]) - len(lines[anchor_b].lstrip())]
    block_b = [
        "%s'%s': '%s'," % (indent_b, key, dart_single_quote(texts[8 + i]))
        for i, key in enumerate(PLAYER_KEYS)
    ]
    lines[anchor_b + 1 : anchor_b + 1] = block_b

    # --- A 组：video_*，插在 video_transcode_settings_title 之前 ---
    anchor_a = find_entry_end(lines, "video_transcode_settings_title")
    indent_a = lines[anchor_a][: len(lines[anchor_a]) - len(lines[anchor_a].lstrip())]
    block_a = [
        "%s'%s': '%s'," % (indent_a, key, dart_single_quote(texts[i]))
        for i, key in enumerate(VIDEO_KEYS)
    ]
    lines[anchor_a:anchor_a] = block_a

    out = eol.join(lines)

    # 回读校验：11 个键各出现且仅出现一次
    for key in VIDEO_KEYS + PLAYER_KEYS:
        cnt = out.count("'%s':" % key)
        if cnt != 1:
            print("!! 校验失败 %s 出现 %d 次 -> %s" % (key, cnt, locale))
            sys.exit(1)

    shutil.copy2(path, os.path.join(BACKUP_DIR, locale + ".dart"))
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(out)

print("完成：%d 个语言文件" % len(T))