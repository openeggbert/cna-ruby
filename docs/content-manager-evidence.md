# `ContentManager`, `Game.Content`, and the two projections that unblocked them

`NEXT.md` listed three BCL decisions between this binding and `ContentManager`. Two of them —
`System.Action`1` and the generic `!!0` — turn out not to be BCL decisions at all: one is a
*language* rule and the other is a callable. The third, `System.IO.Stream`, is in
`docs/stream-projection-design.md`.

This milestone completes `Content.ContentManager` and `Game.Content`, and `Game.Content` was
`Game`'s last missing member, so **`Game` leaves the partial register** — the first of the six
deferred partial runtime types to do so.

## 1. `System.Action`1` is a callable, and the whole reach was measured before deciding

`Action`1` appears in exactly **two** public signatures across the pinned XNA 4.0 Windows profile:

| member | access |
| --- | --- |
| `ContentManager.ReadAsset<T>(String, Action<IDisposable>)` | protected |
| `ContentReader.ReadSharedResource<T>(Action<T>)` | public |

and the IL shows every use is the same three operations — **null-check, store, invoke once with one
argument for a void return**. `Delegate.Combine` and `Delegate.Remove` appear nowhere near it, no
member exposes one as a property, and none is ever compared. There is no delegate identity to
preserve: no multicast list, no removal semantics, no equality.

So it **structurally collapses**, the way `System.IServiceProvider` and `System.IDisposable` already
do: it declares one member, `Invoke(T)`, Ruby's universal callable protocol is `#call`, and a `Proc`,
a lambda, a `Method` and any object defining `call` are all callable. Mapping the identity to `Proc`
would reject three of those four for no measured reason; inventing `CNA::Runtime::Action` would add
an identity the CLR contract does not have. The verifier asserts neither `Action` nor `ActionOfT` was
invented — and fixing that check for a generic identity was itself a small repair, because
`const_defined?("Action`1")` raises rather than answering false.

`ContentReader.InvokeReader<T>` settles what the parameter *means*, which no signature says:

```csharp
if (!typeReader.TargetIsValueType)
{
    IDisposable disposable = (object)result as IDisposable;
    if (disposable != null)
    {
        if (recordDisposableObject != null) recordDisposableObject.Invoke(disposable);
        else                                contentManager.RecordDisposableObject(disposable);
    }
}
```

It is an **override for where a loaded disposable is registered**, not an extra notification. A
supplied callable *replaces* the manager's own bookkeeping rather than adding to it — which is why
an asset read through `ReadAsset` with a callable is not disposed by `Unload`, and why
`ContentManager.Load` (which passes `null`, at `IL_0098`) is the path that fills `disposableAssets`.

## 2. `!!0` was never a BCL type

The dependency frontier reported `ContentManager` as blocked on an unmapped BCL type called `!!0`.
No register entry could ever have supplied that: `!!N` names a generic **method** parameter and `!N`
a generic **type** parameter, and both are language constructs. The classifier now says so, and
`test_dependency_frontier.rb` restates the rule independently — matching only the placeholder
spelling, so it can never excuse a real unmapped identity.

What resolves it is a rule rather than a mapping, recorded in `mapping-rules.json`
`generics.methodProjection`:

> A CLR generic method projects to a Ruby method taking its type arguments as leading positional
> parameters, in declaration order, ahead of the CLR value parameters.

Ruby has no static generics and cannot infer a type argument from a call site, so `T` must be a
*value*; `System.Type` already projects to `Module`, so it is a Ruby `Module`. `Load<Texture2D>("x")`
is `Load(Texture2D, "x")`. This is the **only** rule under which a projected Ruby method may take
more arguments than its CLR signature declares, and the test checks the arity against the
*reference's* declared arities rather than against the implementation.

Measuring the whole `!!0` reach first showed it splits into two unrelated problems, which is why
only one is solved here:

- **`T` as a returned type token** — `ContentManager.Load<T>`, `ContentReader.ReadObject<T>` and
  siblings. `T` is unconstrained and the method *produces* it. That is this milestone.
- **`T` as a blittable array element** — `SetData<T>`/`GetData<T>` on every texture and buffer,
  `DrawUserPrimitives<T>`, `GetBackBufferData<T>`, all constrained `struct, new()`. That is a packed
  binary buffer with an element stride, and a different problem entirely.

## 3. The producer, and the ownership question `Game.Content` had to answer

`Game.Content` could have been a fresh `ContentManager` with its own native handle. It is not, and
the reason is measured:

> *"A game owns exactly one content manager as a **value member**, so this handle borrows rather than
> owns: it answers the same handle every time it is asked, it cannot be destroyed, and it is
> released when the game is."* — `cna_game_get_content_manager_ext`

One XNA `ContentManager` to one CNA content manager. Creating a second native manager for a game
that already has one is exactly the duplication `docs/graphics-device-service-producer-audit.md`
refused for `GraphicsDeviceManager`.

Measured against the current artifact, the borrowed manager is reachable **before the first frame
and outside every callback**, answers the same handle every time, and loads:

```
get_content_manager_ext (no frame yet) -> SUCCESS handle=4294967298
root directory (CNA default)           -> "Content"
load_texture2d(white-1)                -> SUCCESS  w=1 h=1 levels=1 format=0
handle before / inside / after a frame -> all identical
```

`cna_game_set_content_manager_ext` is deliberately **unbound**: the canonical setter *copies*, where
XNA's `set_Content` is a null check and one `stfld`. Replacing a reference and copying a value are
different operations, so the projection replaces the managed reference and does not pretend the
native side moved.

## 4. Caching is XNA's, and measurement is why

`Load<T>` opens with a disposed check, refuses a null-or-empty name, and keys its cache on
`TitleContainer.GetCleanPath(assetName)` under the `StringComparer.OrdinalIgnoreCase` the constructor
gives its dictionary. A hit whose value is not a `T` throws `ContentLoadException` **rather than
reloading**, and a hit that is one is returned as the same object.

That cache has to live on this side, and two measurements say so rather than a preference:

- CNA's typed loaders hand back a **new independently owned handle per call** — eight sequential
  `load_texture2d` calls for one name answered eight distinct handles — documented to survive
  `cna_content_manager_unload` and to be destroyed by the caller.
- CNA's own normalized key is **not XNA's**: it case-folds but does not collapse `./` or `../`, so
  `./white-1` and `white-1` are two native keys and one XNA key. The projection computes XNA's key
  and never consults CNA's; `cna_content_manager_get_normalized_key_size` is unbound for that reason.

## 5. What a supported `T` means

`Load` materializes through a **registry**, not a claim of generic completeness. Exactly one `T` is
supported — `Graphics::Texture2D` — because it is the only XNA asset type this binding projects at
all. Every other `T` raises `ContentLoadException` naming it, which is what XNA does for a type no
reader produces, and `ContentManager.supported_types` is a value a test reads rather than a comment.

The load is qualified against **externally produced** content: MonoGame's own Ms-PL `.xnb` test
corpus, referenced by path through `CNA_TEST_XNB_DIR` and never copied into this repository. Each
fixture ships a manifest stating what it contains, so the assertions are falsifiable rather than
self-confirming — `white-1.xnb` is documented as a 1x1 `Color` texture with one mip level, and that
is what the test asserts.

## 6. Recorded deviations

- **A standalone `ContentManager` cannot load.** `cna_content_manager_create` requires a graphics
  device; XNA's constructor requires nothing. XNA finds the device through
  `ServiceProvider.GetService(typeof(IGraphicsDeviceService))`, and this binding registers no such
  service *on purpose* — the producer audit measured that registering one duplicates a lifecycle
  step CNA has already performed. So a standalone manager is fully constructible and every managed
  member works, and its `Load` refuses by naming the missing service. `Game.Content` is the manager
  that loads.
- **`ReadAsset` does not route through `OpenStream`.** XNA reads the stream `OpenStream` returns, so
  an override redirects where content comes from. CNA's reader takes an asset *name*, and no route in
  the whole 4054-route ABI accepts `.xnb` bytes from a caller-supplied buffer. `OpenStream` is
  projected, works, and answers a real `Stream` over the asset's bytes — its test reads the `XNB`
  magic out of it — but overriding it does not redirect `Load`. Calling it and discarding the result
  to preserve the hook's ordering would double every asset's I/O to simulate a redirection that
  still would not happen.
- **`Dispose` and `Dispose(Boolean)` are one Ruby method** with a default argument, the rule `Game`
  and `GameComponent` already follow, because Ruby cannot give one name two visibilities. The
  protected overload is publicly reachable here, which it is not in the CLR.
- **`set_RootDirectory` on a disposed manager raises `NoMethodError`, not `DisposedObjectError`.**
  It is the only member of the type with no disposed check — it goes straight to `loadedAssets.Count`
  — so XNA throws `NullReferenceException` there. Reproduced rather than smoothed over; a bare
  `rescue` catches it exactly as `catch (Exception)` catches the CLR one.

## 7. A defect that was mine, not CNA's

Four separate probe runs appeared to show `cna_content_manager_load_texture2d` and
`cna_content_manager_load_sprite_font` returning `CNA_RESULT_SUCCESS` with `CNA_INVALID_HANDLE`,
which would have contradicted their documented contracts. It was reproducible and it looked like an
upstream defect worth reporting.

It was the probe. `printf("… %s handle=%llu", R(load(&h)), h)` reads `h` in the same argument list as
the call that writes it, and **argument evaluation order in C is unspecified**, so the read happened
first. Every case where the call was sequenced before the read answered a valid handle; every case
where it was not answered zero. Sequencing the call into its own statement made all four go away.

Recorded because the near-miss is the lesson: a measurement that contradicts a documented contract
is a reason to doubt the measurement first.

## 8. Structural movement

| | before | after |
| --- | --- | --- |
| `TARGET_TYPES` | 150 | 151 |
| `TARGET_MEMBERS` | 1838 | 1849 |
| `COMPLETE_TYPES` | 144 | 146 |
| `PARTIAL_TYPES` | 6 | **5** |
| `MISSING_TYPES` | 107 | 106 |
| `MISSING_MEMBER` | 110 | 109 |
| `TOTAL_DIAGNOSTICS` | 259 | 258 |
| `BCL_PROJECTED_IDENTITIES` | 15 | 17 |
| `ALLOWLIST_ENTRIES` | 0 | 0 |
| bound native functions | 72 | 80 |
| dependency-complete candidates | 11 | 12 |

The frontier grew because completing a type uncovers what it was hiding: `ResourceContentManager`
derives from `ContentManager`, and `GamerServicesComponent` stopped being il-only blocked when
`Game.Content` completed `Game`. `Microphone` lost its BCL half to the `System.Byte[]` decision and
keeps `NATIVE_RUNTIME` alone.
