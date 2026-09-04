# Upstream CNA defect — a loaded `Model` makes process shutdown segfault

**Measured 2026-09-04 against all three qualified artifacts: `~/deps/cna-c-abi-0.21.0` (`HEADLESS`),
`~/deps/cna-c-abi-0.21.0-opengl33` and `~/deps/cna-c-abi-0.21.0-opengles3-fx` (the last two under a
private `Xvfb` with `SDL_VIDEODRIVER=x11`).** All three crash identically.

## The minimal reproduction

One `cna_content_manager_load_model` and nothing else. No view is taken, nothing is destroyed by
hand, the game is disposed normally:

```ruby
game = ProbeGame.new do |g|          # a Game with a GraphicsDeviceManager and a content root
  cm = g.Content.__send__(:native_handle)
  view = CNA::Native::Layouts::StringView.new("BlenderDefaultCube".b)
  out = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
  load_model.call(cm, view.read_u64(0), view.read_u64(8), out)   # answers CNA_RESULT_SUCCESS
end
game.Run
game.Dispose                          # succeeds; "disposed" prints
                                      # → SIGSEGV, exit status 139, during process shutdown
```

| Variant | Exit |
| --- | --- |
| the same probe with no `load_model` call | 0 |
| load, then `cna_content_manager_unload`, then dispose | **139** |
| load, then `ContentManager#Dispose` (`cna_content_manager_destroy`), then dispose | **139** |
| load, dispose, then `exit!(0)` | **0** |
| `cna_model_destroy` on the loaded handle, at any point | **139, immediately** |
| the same `cna_model_destroy` on a **hand-built** `cna_model_create` model | 0 |

## What that pins down

- **It is not the load.** The route answers `CNA_RESULT_SUCCESS` and the model is completely
  correct: two bones (`RootNode` → `Cube`), one mesh `Cube` whose bounding sphere is radius
  1.7320509 — a unit cube's half-diagonal, √3 — one mesh part of 24 vertices and 12 primitives, one
  effect, one vertex buffer and one index buffer, all matching the fixture's own manifest.
- **It is not the managed side.** The reproduction calls the raw route through a bare
  `Fiddle::Function`; there is no Ruby object graph, no view and no finalizer in the path.
- **It is not disposal order.** Unloading the content manager first, destroying it first, or doing
  neither all end the same way, and the crash happens *after* `cna_game_destroy` has already
  returned success.
- **It is a shutdown path.** `exit!(0)` skips `atexit` handlers and static destructors and is
  clean, so what crashes is something the C runtime runs on the way out once a model has been
  loaded — not anything this binding calls.
- **`cna_model_destroy` on a content-loaded model is a second, separate crash.** The header says
  the model owns the handles it publishes and warns against releasing *those* by hand; it says
  nothing about the model handle itself, and a C ABI whose whole design is an exception barrier
  should refuse rather than fault. A hand-built model destroys cleanly, so the difference is the
  content manager's cache.

For contrast, the three **model-owned** resources refuse politely and correctly:
`cna_effect_destroy`, `cna_vertex_buffer_destroy` and `cna_index_buffer_destroy` on a loaded part's
effect and buffers each answer `CNA_RESULT_INVALID_STATE` (3) and change nothing. The bone, mesh,
part and collection **views** are the caller's and destroy cleanly with result 0.

## What this binding does about it

Nothing is worked around and nothing is hidden.

- `Model` is projected in full and `ContentManager.Load(Model, name)` is its producer, because the
  API is correct — only teardown is not.
- **`cna_model_destroy` is not in the manifest.** XNA's `Model` is not `IDisposable`, so no
  projected member wants it; the crash is reachable only by a binding that decided to free the
  handle itself, and this one does not.
- The model's own views are released by `Model#release_content_views`, which `ContentManager#Unload`
  and `#Dispose` call. That path is exercised and clean.
- Every test that loads a real model runs in a **child process** that ends with `exit!`, and
  `ModelTest#test_loading_a_model_still_segfaults_at_shutdown` asserts the crash itself — the same
  child without `exit!` must die on a signal. If a later CNA fixes it, that test fails and the
  workaround comes out.
