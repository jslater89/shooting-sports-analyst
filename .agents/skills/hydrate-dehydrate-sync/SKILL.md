---
name: hydrate-dehydrate-sync
description: Keep UI/domain mappings consistent when editing DB<->domain conversion code. Use when changing methods like `fromHydrated(...)`, `hydrate()`, `asShooter(...)`, or other mapping between Db* entities and domain models.
---

# Hydrate/Dehydrate Sync

## When to Use
Use this skill when:
- The agent changes conversion code between DB schema objects and domain model objects
- The agent changes the meaning, units, or defaults of fields used by the UI
- The agent changes any identity-related mapping that affects equality or map keys

## Instructions
1. **Inventory mapped fields**
   - Identify exactly which fields are read/written in the conversion function(s).
   - Call out nullability/default behavior explicitly.
2. **Find call sites**
   - Locate every place that:
     - constructs a domain object from DB objects
     - or reconstructs DB objects from domain objects
3. **Preserve UI invariants**
   - If the UI sorts/group-builds based on certain fields, confirm they are still populated and correctly computed.
   - Pay attention to display-related computed fields (ratios, places, sigma/oneSigma/twoSigma naming).
4. **Check equality / keys**
   - If any conversion changes how identity is derived (or which IDs are used), confirm all map/set keys still behave correctly.
5. **Cache coherence**
   - If cached objects depend on selection identity (e.g., by ID/hash), ensure caches are invalidated when selection changes.

## “Done” criteria
- The code compiles
- UI hydration paths behave consistently
- Any cache invalidation still matches the object identity rules
