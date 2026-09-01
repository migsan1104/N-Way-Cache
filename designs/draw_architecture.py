#!/usr/bin/env python3
"""Cache_Architecture.png - block diagram regenerated from a full src/ read
(2026-09-01 rewrite for readability). The flow is a NUMBERED story (1-11):
request -> hit path across the top, miss machinery across the bottom, one
clean response rail back to the CPU. All arrows are orthogonal elbows; the
single unavoidable crossing (refill vs miss-descent) is drawn as a hop.
Numbers are the as-built Cache.sv overrides: S-1 input stage, RS_DEPTH=8
(AF=4), MSHR_COUNT=4, MAX_WAITERS=4, Delay(6), registered arbiter outputs.
    python3 draw_architecture.py
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Arc
from matplotlib.lines import Line2D

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 31.5, 16.6
fig, ax = plt.subplots(figsize=(26, 13.8))
ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
ax.set_aspect("equal")

EC = "#1a3a6b"
BLU, GRN, ORG, PUR, RED, GRY = "#1f5fbf", "#2e7d32", "#e07b00", "#7b2fa8", "#c62828", "#555"
C = dict(cpu="#dbe9f6", arr="#ddeedd", mshr="#fdeecd", rs="#fff3d6",
         disp="#efe0f5", resp="#e8e2f2", mem="#fbe0e0", note="#f2f2f2")


def box(x, y, w, h, title, lines=(), fc="#eef", fs=9.5, tfs=12, lw=1.6, tc=EC):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.05",
                                fc=fc, ec=EC, lw=lw))
    if lines:
        ax.text(x + w / 2, y + h - 0.34, title, ha="center", va="center",
                fontsize=tfs, fontweight="bold", color=tc)
        for i, ln in enumerate(lines):
            ax.text(x + w / 2, y + h - 0.76 - i * 0.335, ln, ha="center",
                    va="center", fontsize=fs, color="#222")
    else:
        ax.text(x + w / 2, y + h / 2, title, ha="center", va="center",
                fontsize=tfs, fontweight="bold", color=tc)


def badge(x, y, n, color):
    ax.add_patch(plt.Circle((x, y), 0.235, fc="white", ec=color, lw=1.8, zorder=6))
    ax.text(x, y, str(n), ha="center", va="center", fontsize=10.5,
            fontweight="bold", color=color, zorder=7)


def elbow(pts, color, label=None, lxy=None, num=None, nxy=None, lw=2.6,
          fs=9.6, hop_at=None):
    """Orthogonal polyline with an arrowhead on the last segment.
    hop_at=(x,y): draw a bridge arc where this line crosses another."""
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        if hop_at and y0 == y1 and min(x0, x1) < hop_at[0] < max(x0, x1):
            d = 0.22 * (1 if x1 > x0 else -1)
            ax.add_line(Line2D([x0, hop_at[0] - d], [y0, y0], color=color, lw=lw))
            ax.add_patch(Arc(hop_at, 2 * abs(d), 0.44, theta1=0, theta2=180,
                             color=color, lw=lw))
            ax.add_line(Line2D([hop_at[0] + d, x1], [y0, y1], color=color, lw=lw))
        else:
            ax.add_line(Line2D([x0, x1], [y0, y1], color=color, lw=lw,
                               solid_capstyle="round"))
    (xa, ya), (xb, yb) = pts[-2], pts[-1]
    ax.annotate("", xy=(xb, yb), xytext=(xa, ya),
                arrowprops=dict(arrowstyle="-|>", color=color, lw=lw,
                                mutation_scale=17))
    if num is not None:
        nx, ny = nxy if nxy else pts[0]
        badge(nx, ny, num, color)
    if label:
        lx, ly = lxy
        ax.text(lx, ly, label, fontsize=fs, color=color, fontweight="bold",
                ha="center", va="center",
                bbox=dict(boxstyle="round,pad=0.18", fc="white", ec="none", alpha=0.88))


# ---------------- header -------------------------------------------------
ax.text(0.3, H - 0.30, "Cache - how a request flows",
        ha="left", fontsize=20, fontweight="bold", color=EC)
ax.text(0.3, H - 0.78,
        "16 KB, N-way set-associative (N = 1/2/4/8/16), non-blocking, write-allocate  ·  "
        "line = 4 x 32-bit words, word-addressed CPU  ·  follow the numbers: "
        "hit path 1-5 (top), miss path 6-11 (bottom)",
        ha="left", fontsize=11, color="#444")

# ---------------- top band: the pipeline --------------------------------
for x, w, s in [(3.3, 2.2, "stage S-1"), (6.3, 3.1, "stage S0"),
                (11.0, 4.5, "stage S1"), (18.6, 3.7, "")]:
    if s:
        ax.text(x + w / 2, 14.82, s, fontsize=9.5, color="#888",
                ha="center", style="italic")

box(0.3, 12.3, 2.2, 2.05, "CPU", ["req / resp", "handshake", "out-of-order ids"],
    fc=C["cpu"], tfs=13)
box(3.3, 12.65, 2.2, 1.45, "Input register", ["accepted request", "captured"],
    fc=C["note"], tfs=10.5)
box(6.3, 12.65, 3.1, 1.45, "Address_Decode", ["addr -> tag | set | word"],
    fc=C["cpu"], tfs=11)
box(11.0, 12.25, 4.5, 2.3, "Compare_Select_Replace",
    ["compare tag in every way -> hit / miss", "read hit also needs word_valid[word]",
     "victim = first free way, else PLRU", "decisions registered -> writes land in S2"],
    fc=C["cpu"], fs=9.3, tfs=11.5)

elbow([(2.5, 13.4), (3.3, 13.4)], BLU, num=1, nxy=(2.9, 13.75))
ax.text(2.9, 12.05, "the ONLY stall point:\ncpu_req_ready = hit-FIFO not full\nAND miss queue not almost-full",
        fontsize=8.2, color=GRY, ha="center", va="top", style="italic")
elbow([(5.5, 13.4), (6.3, 13.4)], BLU)
elbow([(9.4, 13.4), (11.0, 13.4)], BLU)

# ---------------- middle band: the arrays -------------------------------
box(4.6, 8.3, 6.7, 2.65, "", fc="#f2f7f2", lw=1.2)
ax.text(5.0, 10.62, "read in S0  ->  registered into S1", fontsize=9,
        color="#3a6b3a", style="italic", ha="left")
box(4.85, 8.5, 1.75, 1.7, "Replacement", ["tree PLRU", "per set"], fc=C["note"],
    fs=8.8, tfs=9.8)
box(6.85, 8.45, 4.2, 1.75, "Flag_Tag_Data_Array  x N ways",
    ["flags: flops   tags: banked RAM", "data: one 1R1W bank per word (SRAM macro on ASIC)"],
    fc=C["arr"], fs=8.8, tfs=10.5)

elbow([(7.85, 12.65), (7.85, 10.95)], GRN, num=2, nxy=(8.25, 11.9),
      label="set index reads\nall ways + PLRU", lxy=(6.1, 11.9))
elbow([(10.5, 10.95), (10.5, 11.55), (11.5, 11.55), (11.5, 12.25)], GRN, num=3,
      nxy=(10.13, 11.3),
      label="per-way tag + flags + line,\n+ the PLRU victim way", lxy=(8.2, 11.15))
elbow([(12.4, 12.25), (12.4, 9.95), (11.3, 9.95)], GRN, num=4, nxy=(12.78, 11.7),
      label="S2 writes: alloc /\nCPU word", lxy=(13.15, 9.55))

# ---------------- right: Response_Unit + back to CPU --------------------
box(18.6, 8.6, 3.7, 2.4, "Response_Unit",
    ["hit FIFO (8) - full => stall", "miss FIFO (8) - has priority", "one response per cycle"],
    fc=C["resp"], fs=9.3, tfs=12)
elbow([(15.5, 12.9), (16.6, 12.9), (16.6, 10.4), (18.6, 10.4)], BLU, num=5,
      nxy=(16.6, 12.3), label="HIT: data + id", lxy=(17.5, 12.9))
elbow([(20.45, 11.0), (20.45, 15.35), (1.4, 15.35), (1.4, 14.35)], BLU,
      label="response to CPU  (hit or miss, request id echoed)", lxy=(11.0, 15.68))

# ---------------- bottom band: the miss machinery -----------------------
box(11.6, 3.5, 5.5, 3.0, "Reservation_Station  (miss queue, 8)",
    ["oldest first; same-line misses MERGE", "into one entry (up to 4 waiters)", "victim line parked in side-buffer",
     "almost-full is the back-pressure brake"],
    fc=C["rs"], fs=9.1, tfs=11)
box(19.0, 3.5, 3.7, 3.0, "MSHR  x 4",
    ["FSM per miss:", "write back dirty victim words,", "then fetch 4 words,", "critical word FIRST"],
    fc=C["mshr"], fs=9.1, tfs=11.5)
box(23.5, 4.6, 3.0, 1.9, "Arbiter", ["oldest stream first,", "beats stay contiguous"],
    fc=C["mshr"], fs=9.1, tfs=11)
box(27.3, 3.4, 3.7, 6.2, "Memory",
    ["single port, id-tagged", "20-cycle read latency", "never back-pressured", "(mem_resp_ready = 1)"],
    fc=C["mem"], fs=9.3, tfs=12.5)
box(22.4, 1.4, 3.4, 1.5, "Response DeMux", ["beat -> MSHR[id]"], fc=C["mshr"],
    fs=9, tfs=10.5)
box(13.0, 0.9, 3.8, 1.7, "Dispacher",
    ["streams 1 CPU response / cycle", "as each word arrives"], fc=C["disp"],
    fs=9, tfs=11.5)
box(18.9, 1.6, 1.9, 0.9, "Delay(6)", fc=C["note"], tfs=9.5)
box(12.0, 7.9, 2.1, 1.4, "MSHR_Mux", ["one refill", "at a time"], fc=C["mshr"],
    fs=8.6, tfs=10)

# 6: miss descends from S1 into the RS
elbow([(14.7, 12.25), (14.7, 6.5)], ORG, num=6, nxy=(15.1, 10.9),
      label="MISS + victim-line snapshot", lxy=(16.65, 7.0))
# 7: issue
elbow([(17.1, 5.0), (19.0, 5.0)], ORG, num=7, nxy=(18.05, 5.35),
      label="oldest ready miss ->\nfree MSHR", lxy=(18.05, 4.35))
# 8: beats to memory
elbow([(22.7, 5.55), (23.5, 5.55)], RED, num=8, nxy=(23.1, 5.95))
elbow([(26.5, 5.55), (27.3, 5.55)], RED, label="mem_req (registered)", lxy=(25.0, 7.0))
# 9: responses back, demuxed to the entries
elbow([(28.6, 3.4), (28.6, 2.15), (25.8, 2.15)], RED, num=9, nxy=(28.95, 2.8),
      label="mem_resp (id, data)", lxy=(28.2, 1.6))
elbow([(22.55, 2.9), (22.55, 3.5)], RED)
ax.text(21.75, 3.1, "4th beat\ncompletes the line", fontsize=8.2, color=RED,
        ha="right", va="center", style="italic")
# data continues left to the Dispacher through Delay(6)
elbow([(22.4, 2.05), (20.8, 2.05)], PUR)
elbow([(18.9, 2.05), (16.8, 2.05)], PUR, label="data, aligned\nwith the retire", lxy=(17.85, 2.85))
# 10: refill up into the arrays (hops over the miss descent)
elbow([(19.8, 6.5), (19.8, 8.35), (14.1, 8.35)], PUR, num=10, nxy=(20.15, 7.5),
      hop_at=(14.7, 8.35),
      label="refill line", lxy=(16.9, 8.72))
elbow([(12.0, 8.35), (11.3, 8.35)], PUR,
      label="drains only words still invalid -\nan early CPU write is never clobbered",
      lxy=(8.3, 7.75))
# 11: retire -> Dispacher -> miss responses rail into the Response_Unit
elbow([(13.85, 3.5), (13.85, 2.6)], PUR, num=11, nxy=(14.2, 3.1))
ax.text(14.55, 3.1, "retire:\nwaiter list", fontsize=8.2, color=PUR, ha="left",
        va="center", style="italic")
elbow([(15.6, 0.9), (15.6, 0.5), (31.1, 0.5), (31.1, 9.95), (22.3, 9.95)], PUR,
      label="MISS responses - critical word first, out of order", lxy=(23.6, 0.88))

# ---------------- footer: the three ideas + legend ----------------------
ideas = [
    ("Sub-line valid bits", "each word has its own valid bit - a write\nmiss writes immediately, no waiting\nfor the fill to come back"),
    ("One brake", "no mid-pipeline stalls; back-pressure\nexists only at cpu_req_ready"),
    ("Non-blocking", "4 misses in flight, same-line waiters\nmerged, responses return out of order"),
]
yi = 7.95
for t, sub in ideas:
    ax.text(0.45, yi, t, fontsize=10.5, fontweight="bold", color=EC)
    ax.text(0.45, yi - 0.33, sub, fontsize=8.5, color="#444", va="top")
    yi -= 0.30 + 0.335 * (sub.count("\n") + 1) + 0.42

leg = [(BLU, "request / hit / response"), (GRN, "array read + write"),
       (ORG, "miss"), (PUR, "refill + miss response"), (RED, "memory port")]
for i, (c, t) in enumerate(leg):
    y = 2.95 - i * 0.40
    ax.add_line(Line2D([0.5, 1.3], [y, y], color=c, lw=3))
    ax.text(1.5, y, t, fontsize=9, color="#333", va="center")
ax.text(0.5, 3.45, "arrow colors", fontsize=9.5, fontweight="bold", color="#333")

ax.text(W - 0.2, 0.08, "generated by designs/draw_architecture.py from src/ (2026-09-01)",
        fontsize=7.5, color="#999", ha="right")

fig.savefig(os.path.join(HERE, "Cache_Architecture.png"), dpi=150,
            bbox_inches="tight", facecolor="white")
print("wrote Cache_Architecture.png")
