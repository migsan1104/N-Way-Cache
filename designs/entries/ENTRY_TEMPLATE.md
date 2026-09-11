# Entry NN(x) — <one-line name>

Status: PLAN | IN PROGRESS | LANDED | REJECTED    Date opened: YYYY-MM-DD
Owner decision points are marked **[DECIDE]**.

## 1. The RTL under attack
- Module(s), signal(s), the exact cone. Quote the current code (short).
- The measurement that names it: census class, count @ slack, which run.
- Why it exists today (the invariant it protects), in one paragraph.

## 2. The change (what, not code)
- Behavioural statement of the new mechanism.
- Interface deltas per module: ports added / removed, bits of state added.
- Timing of every new term: which pipeline cycle, registered or live.
- What is deleted.

## 3. The new RTL (sketch, not written)
- Pseudo-code per module. Marked SKETCH. Nothing here is committed to src/.

## 4. Equivalence and hazards
- Cases where old and new behave differently, and why each is legal.
- Race windows walked cycle by cycle.
- Assertions / checkers kept under `ifndef SYNTHESIS`.

## 5. Verification plan
- Directed test(s), regression (./verify.sh 0.8 and 1.0, all four blocks),
  digit-identical expectation (yes/no, and why not).

## 6. Expected effect and cost
- Genus: which census class moves, WNS/TNS/area expectation, control run.
- P&R: what changes in fanout / placement.
- Cost in flops, compares, ports.

## 7. Dependencies and follow-ons
- What must land first; what this enables.

## 8. Decision log
- Dated bullets: what was decided, by whom, on which measurement.
