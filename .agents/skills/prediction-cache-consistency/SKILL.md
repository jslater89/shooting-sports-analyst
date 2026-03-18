---
name: prediction-cache-consistency
description: Ensure prediction/caching logic stays consistent when prediction configuration or hashing changes (e.g., Bayesian delta configHash). Use when editing prediction odds/delta code, cache reads/writes, or invalidation behavior.
---

# Prediction Cache Consistency

## When to Use
Use this skill when:
- Editing code that reads/writes cached prediction artifacts (e.g., Bayesian deltas, odds)
- Changing how cache keys are computed (e.g., `configHash`)
- Updating cache invalidation/cleanup logic (e.g., “delete stale rows” behavior)

## Instructions
1. **Identify cache key fields**
   - Determine which fields constitute “this cache is valid for these settings”.
2. **Preserve invalidation logic**
   - If the code detects a config mismatch, stale rows must be cleared or safely superseded.
3. **Avoid partial clears**
   - Ensure the scope of deletion matches the intended cache validity boundaries (game-level vs global vs prediction-set-level).
4. **Match read and write semantics**
   - Retrieval logic must use the same hashing semantics as write logic.
5. **Validate downstream display**
   - Confirm UI/probability screens refresh and show updated prediction values after config changes.

## Quick Verification Checklist
- Compile succeeds
- Cache miss causes recomputation (not stale reuse)
- Cache hit reuses correctly with matching configHash
