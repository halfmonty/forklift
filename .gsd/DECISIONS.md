# Decisions

## 2026-09-01 — Cardinal camera orbit

Use a render-only four-view camera orbit (`north`, `east`, `south`, `west`). Physics, collision, pickup, shelf support, and vehicle heading remain in fixed world coordinates. Camera rotation is a Left+Right chord; bare Left/Right retain fork-height control. Continuous yaw is deferred until a general render queue and arbitrary-angle rack-face rendering are justified.

The current implementation status and restart checklist are maintained in the implementation guide.

The desired future interaction is a held camera modifier plus crank-controlled continuous yaw; the modifier is deliberately undecided.
