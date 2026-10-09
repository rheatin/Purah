# Calendar Overflow Strategy & Non-Invasion Architecture Design

## 1. Problem Statement
When a user has many calendar events (e.g., 10 to 30 events in a busy day or week), the previous implementation encountered two critical issues:
1. **Unbounded Rail Growth**: Each event generated a stepped chip with a minimum height ($\ge 24\text{pt}$), causing the total height of the Calendar pod to explode up to $500\text{pt}+$, far exceeding the allocated layout slot (typically $150\text{pt} \sim 200\text{pt}$).
2. **Physical Inter-Pod Invasion**: The unclipped `VStack` physically cascaded downwards and overlapped neighboring pods (Music, Todo), corrupting both the visual hierarchy and mouse hit-test event routing.

## 2. Architecture & Design Principles
To maintain strict plugin decoupling:
- **Zero Base Contamination**: `PurahWorkspaceStore` and the core layout solver remain completely agnostic to Calendar's internal business logic.
- **Plugin-Level Strategy Ownership**: `CalendarPluginState` owns the strategy configuration, persistence, and event prioritization.
- **Generic Rail Containment Guard**: `SteppedRailContainerView` applies a universal rigid height boundary with proportional compression and clipping, protecting all stepped plugins from ever invading adjacent pods.

## 3. Two Core Strategies Configurable in Plugin Settings

### 方案 A：Smart Fold + "+N More" Capsule (`.smartFold`) - Default
- **Temporal Prioritization**:
  1. `NOW` (Ongoing events: `event.isOngoing`)
  2. `SOON` (Imminent events starting within 60 minutes: `event.isImminent`)
  3. `NEXT` (Upcoming events in current time scope, ordered chronologically)
  4. Expired/past events are collapsed first.
- **Capsule Capping**: The rail strictly renders up to `maxRailEvents` chips (default 4, configurable 2...6).
- **"+N More" Aggregation Chip**:
  - If total events $> \text{maxRailEvents}$, the first $(\text{maxRailEvents} - 1)$ chips are displayed as individual event chips.
  - The final slot is rendered as a special "+N More" capsule (`id: "calendar_more_events"`).
  - Hovering an individual chip pops out its single-event card (`CalendarItemDrawerView`).
  - Hovering the "+N More" capsule smoothly extrudes the full scrollable agenda drawer (`CalendarDrawerView`), displaying all events for the current scope with timestamps, locations, calendar colors, and meeting join buttons.

### 方案 B：Continuous Timeline Streamer (`.continuousStream`)
- **Non-Decomposed Ambient Bar**:
  - `isDecomposed` evaluates to `false`.
  - The rail renders a continuous, elegant time gauge (`ProgressTimelineAmbientView`) matching the exact physical height budget without any chip fragmentation.
- **Full Agenda on Hover**:
  - Hovering anywhere on the continuous bar opens the full scrollable agenda drawer.
  - Perfect for users who prefer a minimalist, calm edge bezel regardless of event density.

### Fallback/Standard Mode：All Items with Rigid Guard (`.fullStepped`)
- Renders all event chips, but strictly constrained within `totalHeight` via proportional scaling and `.clipped()` overflow containment.

---
