---
name: ui-provider-model-wiring-contract
description: Prevent common Flutter Provider/ChangeNotifier UI bugs when editing `lib/ui/**`. Use when the agent changes widget/view-model wiring, controller lifecycle, listeners, or cache invalidation.
---

# UI Provider/Model Wiring Contract

## When to Use
Use this skill when editing code that includes any of:
- `ChangeNotifier` / `notifyListeners()`
- `Provider.of`, `context.read`, `ChangeNotifierProvider`
- `StatefulWidget` with controllers/listeners (e.g., `TextEditingController`, `addListener`)
- View-model caches keyed by selection/state (e.g., selected prediction set, selected group)

## Instructions
1. **Listener lifecycle**
   - If listeners are added in `initState`, ensure they are removed in `dispose`.
2. **Controller lifecycle**
   - Dispose `TextEditingController` (and similar) in `dispose` if created.
3. **notifyListeners correctness**
   - After any state mutation that should update the UI, call `notifyListeners()` (or ensure the existing suppression pattern still refreshes later).
4. **Cache invalidation**
   - If caches exist (e.g., computed data based on a selected entity), clear or refresh them when the selection changes.
5. **Tab/list derived data**
   - Ensure tab content uses the correct current selection and does not reuse stale view-model state across tabs.

## “Done” criteria
- No obvious lifecycle leaks
- UI updates occur when expected
- Any selection-based caches are coherent
