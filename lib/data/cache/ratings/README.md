## Rating Cache in Single-Isolate and Multi-Isolate Modes

This directory now mirrors the match cache pattern with a mode-aware rating cache:

- `RatingCache` is the shared interface (`rating_cache.dart`).
- `MemoryRatingCache` is the default in-process implementation (`memory_rating_cache.dart`).
- `IsolateRatingCacheClient` and `IsolateRatingCacheServer` provide an isolate-safe implementation (`isolate/isolate_rating_cache.dart`).
- `isolate/commands.dart` defines message contracts between client isolates and the rating cache server isolate.

### Why This Exists

The previous "local map cache" approach works in a single isolate, but each isolate has its own memory.
In multi-isolate server contexts, rating lookups and writes need a single owner isolate to avoid divergent cache state.

### Runtime Selection

`RatingCache.instance` selects behavior from `FlutterOrNative.isolateModeProvider.kMultiIsolateMode`:

- **Single-isolate mode (`false`)**: falls back to `MemoryRatingCache`.
- **Multi-isolate mode (`true`)**: requires an isolate-aware cache instance to be set before use.

If multi-isolate mode is enabled and no isolate-aware cache has been registered, `RatingCache.instance` throws to prevent accidental use of per-isolate local state.

### Isolate Pattern and the Toy Example

The rating cache implementation follows the same manager/client/server messaging model used in:

- `lib/server/isolate/isolate_client.dart`
- `lib/server/isolate/isolate_server_helper.dart`
- `lib/server/isolate/example/hello_world_isolate_example.dart`

Conceptually:

1. Start and register the manager isolate.
2. Spawn/register the rating cache server isolate (`IsolateRatingCacheServer`).
3. On each client isolate, set up an `IsolateManagerClient`.
4. Create/connect an `IsolateRatingCacheClient`.
5. Register that client as the active cache implementation via `RatingCache.setInstance(...)`.

After that, `lookupRating`, `cacheRating`, invalidation, and clear operations are forwarded by command message to the cache server isolate.

### Analyst Database Sync Behavior in Multi-Isolate Mode

`AnalystDatabase` now has explicit async and sync rating cache paths:

- Async methods (`lookupCachedRating`, `cacheRating`, `clearLoadedShooterRatingCache`) delegate to `RatingCache.instance`.
- Sync methods (`lookupCachedRatingSync`, `cacheRatingSync`, `clearLoadedShooterRatingCacheSync`) intentionally **do nothing** (or return `null`) when `kMultiIsolateMode` is true.

This fallback is deliberate: synchronous local-cache access is not isolate-safe in multi-isolate mode, so callers must rely on the isolate-based cache path. If that isn't available, they should hit the database
(which is isolate-safe).

### Current Server Defaults

`bin/server.dart` and `bin/db_oneoffs.dart` currently configure `ServerDebugProvider(isMultiIsolate: false)`, so they run in single-isolate mode unless changed.

When enabling true multi-isolate server execution, also ensure isolate-aware cache setup is completed during startup.
