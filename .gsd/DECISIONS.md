# Decisions

## 2026-09-01 — Cardinal camera orbit

Use a render-only four-view camera orbit (`north`, `east`, `south`, `west`). Physics, collision, pickup, shelf support, and vehicle heading remain in fixed world coordinates. Camera rotation is a Left+Right chord; bare Left/Right retain fork-height control. Continuous yaw is deferred until a general render queue and arbitrary-angle rack-face rendering are justified.

The current implementation status and restart checklist are maintained in the implementation guide.

The desired future interaction is a held camera modifier plus crank-controlled continuous yaw; the modifier is deliberately undecided.

## 2026-09-03 — Native audio authoring tool

Build a public static web editor around one constrained, language-neutral audio document. It authors only the hardware-validated Playdate profile: four monophonic music tracks and native waveform/ADSR effect presets. It exports Zig, C, and Lua adapters. MIDI import, arbitrary tracker effects, custom generators, and exact desktop audio emulation are deferred.

The complete contributor implementation plan is in docs/PDNA_TOOL_IMPLEMENTATION_PLAN.md.

## 2026-09-04 — Bounded native audio expression

PDNA v2 will use native envelopes, LFOs, sequence control signals, and bounded key-range percussion voices. Pitch vibrato and pitch-slide automation are mutually exclusive per voice; filters require a separate dedicated-channel hardware spike. The plan is in docs/PDNA_EXPRESSIVE_AUDIO_PLAN.md.

## 2026-09-05 — Campaign before content production

Before M18 authors warehouse content, Forklift Certified will gain a static campaign flow: title, ordered stages and shifts, boss briefings, shift-scoped time/damage scoring, completed-shift progression saves, stage promotions, and a final win state. Stages continue to select compile-time static levels; no generic runtime level format is introduced. The implementation guide defines M17b.
