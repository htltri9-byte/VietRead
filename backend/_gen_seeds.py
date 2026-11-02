# -*- coding: utf-8 -*-
"""Sinh seed lists từ dữ liệu từ điển THẬT (offline, không mạng) — chạy 1 lần rồi xoá.

Chỉ kiểm chứng against `vietphrase.txt` cục bộ; KHÔNG gọi mạng, KHÔNG AI.
Ứng viên do người viết chắt lọc: 8 khóa ví dụ bắt buộc + khóa trong chương
Qidian thật + từ thường gặp trong truyện.
"""
from __future__ import annotations

import io
import os
import sys
from pathlib import Path

sys.path.insert(0, os.getcwd())
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

from app import marking, vietphrase  # noqa: E402

DICT = Path("dictionaries")

# --- Ứng viên ambiguous ---------------------------------------------------
# 8 khóa ví dụ bắt buộc từ đề bài:
SPEC8 = "打 行 开 过 意思 东西 方便 厉害".split()

# Khóa thật gặp trong chương Qidian 第1章永夜 (đa nghĩa rõ rệt, KHÁC ý):
QIDIAN_AMB = """
就是 肚子 冷气 叶片 风声 动静 心里 当时 手脚 至于 重新 遍 让 年景 情绪 院落
光彩 打量 端详 打算 盘算 计较 较量 揣摩 揣测 猜测 猜疑 疑心 疑惑 打磨 磨练
收拾 折腾 磨蹭 耽误 搭理 挑剔 数落 唠叨 念叨 摆布 摆弄 颠倒 翻腾 消遣 消磨
过来 过去 拐弯 抹角 敲打 拉扯 起开 让开 闪开 滚开 见过 意思 东西 方便 厉害
""".split()

# Từ thường gặp trong truyện — đa nghĩa rõ rệt:
COMMON_AMB = """
客气 麻烦 老实 机关 大夫 光景 把握 摆脱 包袱 本来 比较 表示 差不多 当然 到底 多少 反正
丰富 负责 复杂 感情 功夫 关系 规矩 好像 合适 后来 几乎 记得 技术 检查 结果 解决 介绍 经过
经济 举行 觉得 决定 开始 考虑 可能 可是 力量 例子 练习 了解 邻居 毛病 明白 名字 努力 偶然
便宜 漂亮 平常 其实 千万 巧合 清楚 情形 请求 确实 热闹 人家 认识 任务 容易 如果 身上
生气 声音 失败 师傅 十分 时候 世界 事情 手段 熟悉 水平 思想 随便 态度 特别 提高
天气 条件 听说 同事 突然 危险 位置 味道 文化 问题 希望 喜欢 显得 现在 相反 消息 小心 兴趣
需要 学问 应该 因为 一直 一起 一点 影响 证明 之间 祝福 专门 转变 准备 公主 少爷 老爷 夫人
师兄 师妹 道友 宗门 门派 天才 废物 妖兽 灵气 丹药 家伙 门路 心肠 心事 眉目 风头 市面 场面
教训 印象 理由 根据 准则 规则 方案 方针 政策 道理 方法 方式 手法 套路 体面 脸面 面子 排场
气氛 氛围 声势 阵势 架势 样子 模样 形状 形态 状态 姿态 态势 事态 局势 下场 结局 收场 收尾
线索 传闻 谣言 夜里 时刻 时候 关头 机会 时机 机遇 空子 由头 借口 权利 权益 权限 职责 义务
责任 担子 负担 干系 关联 牵连 牵涉 涉及 介意 在乎 计较 情面 交情 友情 热情 盛情 深情 真情
心意 心情 心绪 心态 气色 神色 脸色 眼神 目光 视线 方向 方位 部位 地方 处所 场所 场地 区域
价钱 价格 价值 代价 成本 费用 开销 支出 收入 收益 利益 好处 益处 弊处 坏处 害处
""".split()

COMMON_AMB3 = """
出路 退路 后路 生路 绝路 死路 门路 邪路 正路 弯路 绕路 小路 大路 官路 私路
心情 心事 心意 心肠 心眼 心结 心病 心事 心结 心头 心坎 心底 心腹 心腹 心腹
消息 音信 信儿 口信 风声 口风 口气 口吻 语调 语气 语病
意思 意图 意愿 心愿 志向 抱负 理想 梦想 幻想 妄想 空想 遐想 联想 设想 构想
场面 局面 战局 棋局 布局 时局 政局 变局 残局 终局 收场 开场 冷场 出场 上场 下场
主张 主见 主意 见解 见地 眼光 眼力 目光 视角 视野 见识 见闻 耳闻 耳目
分寸 尺寸 深浅 轻重 厚薄 大小 多少 高低 优劣 强弱 弱强 文武 老少 男女 长幼
风度 气度 雅量 胸襟 肚量 气量 度量 容量 数量 质量 分量 重量 剂量 流量
形势 形貌 形象 形迹 行迹 行径 行为 举动 举止 作风 做派 派头 架势 姿势 站相
名堂 门道 道道 奥妙 窍门 秘诀 妙诀 锦囊 计策 计谋 方略 谋略 战略 战术
痕迹 线索 真相 实情 底细 底牌 底线 底气 根底 家底 班底 老底 内情 隐情
心思 心计 心机 心术 心路 用心 存心 有心 无心 粗心 小心 耐心 恒心 决心
心肠 心意 心疼 心爱 心虚 心慌 心急 心切 心软 心硬 心狠 心细 心粗
关口 关卡 关键 节眼 节骨眼 步步 步骤 步调 进程 进度 程序 程度 差距 距离
""".split()

# --- Ứng viên đồng nghĩa ---------------------------------------------------
# Từ trong chương Qidian thật mà các nghĩa CÙNG một ý:
SYN_QIDIAN = """
食物 村庄 岁月 轻微 稍微 忽然 渐渐 自己 不好 平复 直接 虽然 昏昏沉沉 头脑 轮廓 阿婆
晃动 淹没 被子 渣子 刺痛 略带 隔壁 办法 过意不去 不断 光泽 苍白 而且 明显 心有余悸
来临 一些 一片 看不真切 结实 铁锨 快速 打开 布袋 撞击 光芒 惊讶 估计 顿时 腾腾 熄灭 多日
耗尽 接济 争吵 知道 愧疚 当初 呼喊 接受 已经 不要说 随时 和 瘦 使 需 看 白昼 转机 到来
得了 还是 两个孩子 已早 不想 口舌 传说 太阳 一切 夫妻 岁月 生活 非常 显然 感觉 发现
""".split()

# Từ thường gặp — toàn bộ là đồng nghĩa:
SYN_COMMON = """
马上 立刻 通常 平时 常常 终于 慢慢 突然 已经 曾经 老是 总是 从来 一向 永远
互相 一同 一齐 分别 各自 难怪 怪不得 无非 不过 好在 也许 大概 恐怕 或许 究竟
竟然 居然 果然 亲手 顺路 特意 特地 有意 迅速 缓缓 逐步 逐渐 屡次 再三 一再
仿佛 好似 犹如 宛如 恰似 正如 一如 殊不知 熟视无睹 视而不见
""".split()


def validate(keys: list[str], name: str, drop_hv: bool) -> list[str]:
    seen: set[str] = set()
    ok: list[str] = []
    dropped: list[tuple[str, str]] = []
    for k in keys:
        if not k or k in seen:
            continue
        seen.add(k)
        alts = vietphrase._vp_alts.get(k)
        if not alts:
            dropped.append((k, "không có trong từ điển"))
            continue
        merged = marking.merge_similar(list(alts))
        if len(merged) < 2:
            dropped.append((k, "sau gộp <2: " + " | ".join(merged)))
            continue
        hv = marking._is_hanviet_native_pair(
            k, [marking.normalize_meaning(m) for m in merged]
        )
        if drop_hv and hv and k not in SPEC8:
            dropped.append((k, "HV-pair → luật 2b tự xử lý: " + " | ".join(merged)))
            continue
        ok.append(k)
    print(f"== {name}: {len(ok)} hợp lệ / {len(dropped)} bị loại")
    for k, why in dropped:
        print(f"   LOẠI {k}: {why}")
    return ok


def main() -> None:
    vietphrase.load()
    amb = validate(
    SPEC8 + QIDIAN_AMB + COMMON_AMB + COMMON_AMB3, "AMBIGUOUS", drop_hv=True
)
    syn = validate(SYN_QIDIAN + SYN_COMMON, "SYNONYMS", drop_hv=False)
    # Người dùng thắng: khóa đã ở synonyms thì không nằm trong ambiguous seed
    amb = [k for k in amb if k not in set(syn)]
    print(f"TỔNG: ambiguous={len(amb)} synonyms={len(syn)}")

    DICT.mkdir(exist_ok=True)
    header_amb = (
        "# ambiguous.seed.txt — Danh sách TRẮNG ĐÓNG GÓI kèm repo: khóa ĐA NGHĨA\n"
        "# THẬT SỰ (người viết chắt lọc từ từ điển + chương Qidian thật, KHÔNG sinh\n"
        "# bằng AI/gọi mạng). Nạp tiếp sau ambiguous.txt của người dùng; khi hai bên\n"
        "# mâu thuẫn thì file người dùng thắng (xem app/marking.py → reload_lists).\n"
        "#\n"
        "# Format: mỗi dòng MỘT khóa chữ Trung, UTF-8; # là chú thích. Sửa file\n"
        "# xong không cần restart (get_lists tự nạp lại) hoặc bấm\n"
        "# POST /dictionary/mark-lists/reload.\n"
        "#\n"
        "# Lưu ý: khóa chỉ được đưa vào đây nếu từ điển còn ≥2 nghĩa SAU khi gộp\n"
        "# trùng/gộp nghĩa gần giống (nhiều khóa tên truyện như 结丹/筑基 có 1 nghĩa\n"
        "# sẽ không có ở đây — không tạo marker là đúng).\n"
    )
    header_syn = (
        "# synonyms.seed.txt — Danh sách ĐEN ĐÓNG GÓI kèm repo: khóa các nghĩa\n"
        "# CHỈ LÀ ĐỒNG NGHĨA (cùng một ý, khác cách nói) — không bao giờ tạo marker\n"
        "# ở mức Vừa/Ít. Nguồn: khóa gây phiền trong chương Qidian thật + từ phổ\n"
        "# biến; do người viết phân loại, KHÔNG sinh bằng AI/gọi mạng. Người dùng\n"
        "# thắng khi mâu thuẫn với ambiguous.txt (xem app/marking.py → reload_lists).\n"
        "#\n"
        "# Format: mỗi dòng MỘT khóa chữ Trung, UTF-8; # là chú thích. Sửa file\n"
        "# xong không cần restart hoặc bấm POST /dictionary/mark-lists/reload.\n"
    )
    (DICT / "ambiguous.seed.txt").write_text(
        header_amb + "\n".join(amb) + "\n", encoding="utf-8"
    )
    (DICT / "synonyms.seed.txt").write_text(
        header_syn + "\n".join(syn) + "\n", encoding="utf-8"
    )
    print("Đã ghi dictionaries/ambiguous.seed.txt và synonyms.seed.txt")


if __name__ == "__main__":
    main()
