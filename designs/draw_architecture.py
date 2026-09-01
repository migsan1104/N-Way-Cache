#!/usr/bin/env python3
"""Cache_Architecture.png - block diagram regenerated from a full src/ read
(2026-08-31). MSHR_File is opened up: Reservation_Station and Dispacher are
first-class blocks with internals. Numbers are the as-built Cache.sv
overrides: S-1 input stage (E28A), RS_DEPTH=8/AF=4, MSHR_COUNT=4,
MAX_WAITERS=4, Delay(6), registered arbiter outputs (E23b).
    python3 draw_architecture.py
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 31.0, 17.5
fig, ax = plt.subplots(figsize=(25, 14.1))
ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")

C = dict(cpu="#dbe9f6", arr="#ddeedd", csr="#dbe9f6", mshr="#fdeecd",
         rs="#fff7e0", disp="#efe0f5", resp="#e8e2f2", mem="#fbe0e0", note="#f4f4f4")
EC = "#1a3a6b"

def box(x, y, w, h, title, lines=(), fc="#eef", fs=10, tfs=12, ec=EC, lw=1.6):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.06", fc=fc, ec=ec, lw=lw))
    ax.text(x + w/2, y + h - 0.33, title, ha="center", va="center", fontsize=tfs, fontweight="bold", color=EC)
    for i, ln in enumerate(lines):
        ax.text(x + w/2, y + h - 0.78 - i*0.35, ln, ha="center", va="center", fontsize=fs, color="#222")

def arrow(p0, p1, color, label=None, lw=2.4, ls="-", rad=0.0, fs=9.5, lofs=(0, 0.18)):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=16, color=color,
                                 lw=lw, linestyle=ls, connectionstyle=f"arc3,rad={rad}"))
    if label:
        ax.text((p0[0]+p1[0])/2 + lofs[0], (p0[1]+p1[1])/2 + lofs[1], label,
                fontsize=fs, color=color, ha="center", fontweight="bold")

BLU, GRN, ORG, PUR, RED, GRY = "#1f5fbf", "#2e7d32", "#e07b00", "#7b2fa8", "#c62828", "#555"

ax.text(W/2, H-0.35, "Cache — architecture and miss machinery (regenerated from src/, 2026-08-31)",
        ha="center", fontsize=19, fontweight="bold", color=EC)
ax.text(W/2, H-0.82, "CACHE_BYTES / ASSOC parameterized (16KB, N∈{1,2,4,8,16}) · 4×32b words per line, word-addressed CPU · "
        "RS_DEPTH=8 (AF=4) · MSHR_COUNT=4 · MAX_WAITERS=4 · params: EN_SRAM_MACRO, TAG_READ_ONEHOT (ASIC)",
        ha="center", fontsize=10.5, color="#444")

# stage rails
for x, s in [(2.6, "S-1 input reg (E28A)"), (5.0, "S0 decode/read"), (8.2, "S1 compare"),
             (11.6, "S2 grants/queues"), (16.4, "S3+ miss machinery"), (27.2, "memory")]:
    ax.plot([x, x], [0.5, H-1.25], ls=":", color="#999", lw=1)
    ax.text(x + 0.08, H-1.5, s, fontsize=9.5, color="#666", ha="left")

# ---------------- left: CPU, S-1, S0, arrays, S1 ----------------
box(0.15, 12.4, 2.1, 2.0, "CPU", ["req valid/ready", "addr,write,wdata,id", "resp valid/ready", "(out-of-order ok)"], fc=C["cpu"], fs=9)
box(2.9, 12.5, 1.9, 1.8, "input regs\n(S-1)", ["accepted req", "registered;", "cpu_req_fire only"], fc=C["note"], fs=8.5, tfs=10)
box(3.3, 9.6, 2.7, 1.9, "Address_Decode", ["tag / set / word split", "pre-compares for the", "E20/E25 elder patch"], fc=C["cpu"], fs=9.5)
box(5.6, 12.0, 4.4, 3.4, "Flag_Tag_Data_Array × N ways",
    ["flags: flops (alloc/dirty/word_valid[4])", "tags: banked LUTRAM / SRAM macro", "data: 1R1W bank per line word",
     "refill DRAINS bank-at-a-time; CPU", "write has priority; partial refill legal", "(sub-line valid = abandonable drain)"],
    fc=C["arr"], fs=9, tfs=11.5)
ax.text(7.8, 15.55, "per-way rindex_rep_r replica regs feed each way's tag banks (E28A/E33)", fontsize=8, ha="center", color="#555")
box(5.6, 8.2, 2.5, 1.5, "Replacement", ["tree PLRU per set", "registered lookup"], fc=C["note"], fs=9)
box(5.9, 3.6, 4.0, 3.9, "Compare_Select_Replace",
    ["S1: per-way tag compare;", "write hits on tag alone, read", "also needs word_valid[word]",
     "one-hot hit + victim selects", "(E36(b) AND-OR victim capture)", "S2 regs: write grants + victim snap"],
    fc=C["csr"], fs=9.5)

arrow((2.25, 13.4), (2.9, 13.4), BLU, "fire", fs=8.5)
arrow((3.9, 12.5), (4.4, 11.5), BLU, "", rad=-0.15)
arrow((4.8, 13.0), (5.6, 13.4), GRN, "rindex (S-1)", rad=-0.1, fs=8.5)
arrow((6.0, 10.6), (6.6, 7.5), BLU, "dec_* regs", rad=0.1, lofs=(-0.75, 0))
arrow((7.7, 12.0), (7.8, 7.5), GRN, "registered/live read:\nline·tag·flags ×N", lofs=(1.15, 0), fs=8.5)
arrow((6.8, 8.2), (7.0, 7.5), PUR, "way", fs=8.5, lofs=(0.3, -0.02))
ax.add_patch(FancyArrowPatch((7.2, 3.55), (5.8, 11.95), arrowstyle="-|>", mutation_scale=14,
                             color=PUR, lw=1.8, connectionstyle="arc3,rad=0.5", linestyle="--"))
ax.text(4.5, 6.0, "S2 write grants:\nalloc_wen / cpu_write_wen\n+ PLRU update", fontsize=8.5, color=PUR, ha="center")

# ---------------- MSHR_File container ----------------
box(10.4, 0.7, 12.0, 12.2, "", fc="#fdf6e3", ec="#b8860b", lw=2.2)
ax.text(10.7, 12.55, "MSHR_File  (owns the whole miss path)", fontsize=13, fontweight="bold", color="#8a6508", ha="left")

# Reservation Station
box(10.8, 6.2, 5.7, 5.9, "Reservation_Station — 8 entries, rs[0] oldest", [], fc=C["rs"], tfs=11)
ax.text(13.65, 11.4, "ordered queue: append at tail, retire = shift down; no age counters", fontsize=8.5, ha="center", color="#555")
tx, ty, tw = 11.1, 7.9, 3.5
for i in range(4):
    yy = ty + 3.2 - (i+1)*0.8
    ax.add_patch(Rectangle((tx, yy), tw, 0.8, fc="white", ec="#aaa", lw=0.8))
    lbl = ["rs[0] — OLDEST, retires", "rs[1]", "…", "rs[7] — tail, allocs"][i]
    ax.text(tx + tw/2, yy + 0.55, lbl, fontsize=8.5, ha="center", fontweight="bold" if i == 0 else "normal")
    if i < 2:
        ax.text(tx + tw/2, yy + 0.2, "line_addr · way · write/wdata · mshr_id · in_progress", fontsize=6.8, ha="center", color="#333")
ax.text(tx + tw/2, ty - 0.28, "+ waiters[4]: (cpu_id, word_id) — same-line misses MERGE\n(CAM runs a cycle early on pre_line_addr; merge_sel_r registered)", fontsize=8, ha="center", color="#8a3d00")
box(14.9, 7.6, 1.4, 3.3, "vbuf", ["victim side-", "buffer (static", "circular):", "META tag/wv +", "per-word DATA", "banks (E18)"], fc="#f2ead2", fs=7.8, tfs=9.5)
ax.text(15.6, 7.35, "slot = head+i", fontsize=7.5, ha="center", color="#555")
ax.text(11.0, 6.55, "alloc_ready = !almost_full (AF=4 of 8) — the ONE brake in the pipe", fontsize=8.5, color="#8a3d00", ha="left")
ax.text(11.0, 6.24, "issue: oldest valid & !in_progress → any free MSHR entry", fontsize=8.5, color="#555", ha="left")

# MSHR entries / demux / mux
box(17.0, 7.6, 3.0, 4.5, "MSHR_Entry × 4", ["FSM: S_IDLE →", "S_ISSUE_W (dirty victim,", " reads vbuf via wb_*,", " skips invalid words)", "→ S_ISSUE_R (4 beats,", " critical word first)", "→ S_WAIT_R: fill_line;", "4th beat → refill_wen"], fc=C["mshr"], fs=8.8, tfs=11)
box(20.3, 8.7, 1.9, 1.7, "Response_\nDeMux", ["valid routed by", "mem_resp_id;", "data broadcast"], fc=C["mshr"], fs=8, tfs=9)
box(17.0, 5.7, 3.0, 1.4, "MSHR_Mux", ["lowest refill_wen →", "single array write;", "retire_sel mirrors it"], fc=C["mshr"], fs=8.5, tfs=10)

# Dispacher
box(10.8, 1.1, 8.0, 4.2, "Dispacher — double-buffered dispatch contexts", [], fc=C["disp"], tfs=11)
for k, xx in [(0, 11.4), (1, 14.4)]:
    box(xx, 1.85, 2.6, 2.3, f"ctx {k}", ["word_data[4]", "cpu_ids/word_ids[4]", "ready_r / sent_r"], fc="white", fs=8, tfs=9)
ax.text(14.8, 4.65, "capture: beats land in newest ctx, critical word first, +3 wrap (beats_left)", fontsize=8.5, ha="center", color="#555")
ax.text(14.8, 1.5, "send: drain oldest ctx — first ready&!sent waiter → one CPU response per cycle", fontsize=8.5, ha="center", color="#6a1b9a")
ax.text(17.9, 3.1, "retire loads the free\nctx while the other\nstill drains (E9)", fontsize=8, ha="center", color="#555")

# flows around MSHR_File
arrow((9.9, 5.2), (10.8, 8.8), ORG, None, rad=-0.25)
ax.text(9.55, 3.15, "miss: addr/way/wdata\n+ victim snapshot → RS alloc", fontsize=9, color=ORG, ha="center", fontweight="bold")
arrow((16.5, 9.6), (17.0, 9.6), ORG, "issue", fs=9)
arrow((17.0, 8.9), (16.3, 8.85), GRY, None)
ax.text(16.65, 8.15, "wb_*: one victim\nword per beat", fontsize=7.8, color=GRY, ha="center")
arrow((17.6, 5.7), (9.85, 5.35), PUR, "refill set/tag/way/line → drain into banks", rad=-0.1, lofs=(1.5, -0.3), fs=9)
arrow((18.5, 7.6), (14.6, 5.3), ORG, None, rad=0.15)
ax.text(18.6, 7.32, "retire → dispatch: waiter list", fontsize=8.5, color=ORG, ha="center", fontweight="bold")

# ---------------- right: arbiter + memory + delay ----------------
box(22.9, 9.7, 3.1, 3.0, "MSHR_Request_Arbiter", ["order FIFO of entry ids", "by issue_pending rise:", "beats stay contiguous,", "no cutting in line.", "mem_req_* REGISTERED", "(+1 cyc, E23b)"], fc=C["mshr"], fs=8.8, tfs=10)
box(27.5, 8.9, 3.2, 3.0, "Memory / RAM_ID", ["single port, ID tagged", "20-cycle read latency", "mem_resp_ready ≡ 1", "(no backpressure,", "by design)"], fc=C["mem"], fs=9)
box(23.6, 4.9, 2.6, 1.5, "Delay(6)", ["aligns mem_resp_rdata", "with retire broadcast"], fc=C["note"], fs=8.8, tfs=10.5)

arrow((20.0, 11.3), (22.9, 11.3), RED, "req valid/write/addr/wb_data", fs=8.5)
arrow((26.0, 11.3), (27.5, 10.9), RED, "mem_req_*", fs=8.5)
arrow((27.6, 9.0), (22.2, 9.4), RED, "mem_resp valid/id/rdata", rad=0.1, lofs=(0.9, -0.45), fs=8.5)
arrow((25.6, 9.05), (24.9, 6.4), RED, "", rad=0.2)
arrow((23.6, 5.4), (18.8, 3.7), RED, "delayed_miss_data", rad=-0.08, lofs=(1.35, 0.3), fs=8.5)
arrow((23.3, 12.4), (20.0, 12.0), GRY, "issued (one-hot) → issue_done", fs=8, lofs=(0.3, 0.3))

# ---------------- Response_Unit + CPU response ----------------
box(3.4, 0.6, 4.8, 2.3, "Response_Unit", ["hit FIFO: FWFT depth 8, full → hit_ready", "miss FIFO: FIFO_NF depth 8 — NO full flag,", "credit-bounded by RS/MSHR; priority over hits"], fc=C["resp"], fs=8.8)
arrow((7.0, 3.6), (6.9, 2.9), BLU, "hit: cmp_rdata/id", fs=9, lofs=(1.35, 0.1))
arrow((10.8, 2.3), (8.2, 2.0), PUR, "miss_valid/data/id", fs=8.5, lofs=(0.2, 0.3))
arrow((3.4, 1.8), (1.0, 12.4), BLU, "cpu_resp_* (OOO, id echoed)", rad=-0.35, lofs=(-1.3, 0), fs=9)
ax.text(1.7, 8.7, "cpu_req_ready =\nhit_ready &&\nmshr_alloc_ready", fontsize=8.5, color="#8a3d00", ha="center")

# legend
box(25.4, 0.6, 5.4, 3.1, "Legend", [], fc="white")
for i, (c, t) in enumerate([(BLU, "CPU request / response"), (GRN, "array read"), (ORG, "miss / RS / MSHR"),
                            (PUR, "refill + miss responses"), (RED, "memory port"), (GRY, "control / handshakes")]):
    yy = 3.15 - i*0.4
    ax.plot([25.7, 26.4], [yy, yy], color=c, lw=3)
    ax.text(26.55, yy, t, fontsize=9, va="center")

fig.savefig(os.path.join(HERE, "Cache_Architecture.png"), dpi=150, bbox_inches="tight")
print("wrote Cache_Architecture.png")
