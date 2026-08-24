# Curve Family Evidence

This document records the managed-only Foundation Milestone 4 closure. The authority is the Microsoft XNA Framework 4.0 Windows runtime assembly `Microsoft.Xna.Framework.dll`, SHA-256 `38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130`, together with its public metadata and method IL. CNA and sibling bindings were engineering references only. The implementation adds no CNA call or native ABI member.

## Exact structural closure

The synthetic enum `value__` fields are excluded by the existing formal Ruby rule.

| Type | Kind | Expected members | Target members | Local diagnostics |
| --- | --- | ---: | ---: | ---: |
| `Curve` | class | 11 | 11 | 0 |
| `CurveKey` | class | 15 | 15 | 0 |
| `CurveKeyCollection` | class | 13 | 13 | 0 |
| `CurveContinuity` | enum | 2 | 2 | 0 |
| `CurveLoopType` | enum | 5 | 5 | 0 |
| `CurveTangent` | enum | 3 | 3 | 0 |

All local type-kind, base/interface, field/property, method-signature, parameter, return, overload, generic, enum/flags, event/operator, and language-mapping categories are zero. The global target is 39 types / 1102 members: 32 complete, the same seven native/runtime types partial, and 218 missing.

The non-flags enum values are exact typed frozen values: `CurveContinuity` Smooth 0 and Step 1; `CurveTangent` Flat 0, Linear 1, and Smooth 2; `CurveLoopType` Constant 0, Cycle 1, CycleOffset 2, Oscillate 3, and Linear 4.

## CurveKey reference behavior

`CurveKey` is an XNA reference class, not a value-semantic struct. Its two- and four-argument constructors initialize both tangents to zero where omitted and Continuity to Smooth; the five-argument form retains the supplied continuity. Position is immutable after construction. Value, TangentIn, and TangentOut are writable Single values and narrow at every public boundary; Continuity is writable through the typed enum bridge.

Collection insertion and retrieval retain the same key object. `Clone` creates a distinct key with copied scalar/enum state, so later field mutation is independent. Equality is field equality over Position, Value, TangentIn, TangentOut, and Continuity, not reference identity; consequently a key containing NaN is not even equal to itself. Operators use the same relation. `GetHashCode` is the unchecked Int32 sum of the five XNA field hashes, using CLR Single hashing (canonical zero and NaN behavior), rather than Ruby's object hash.

`CompareTo` reproduces XNA's direct Single branches: equal positions return zero, a smaller position returns -1, and every other case returns 1. Thus +0 and -0 compare equal, while NaN compared with finite, finite compared with NaN, and NaN compared with NaN all return 1. Collection insertion uses this comparison rather than Ruby `<=>`.

## CurveKeyCollection projection and behavior

The metadata retains `ICollection<CurveKey>`, `IEnumerable<CurveKey>`, and `IEnumerable`. Their selected methods are projected directly on `CurveKeyCollection`; no fake public `System::Collections::Generic` namespace exists. The CLR `Item[index]` property maps formally to `[]` and `[]=`, with both accessor identities and mutability measured. `GetEnumerator` maps to a fresh Ruby `Enumerator`, not the collection itself. The class deliberately does not mix in `Enumerable`, so Ruby helper names do not leak into the strict XNA surface.

`Add` uses the XNA `List<CurveKey>.BinarySearch` insertion algorithm. Positions are ascending, and a successful equal-position search scans forward and inserts after the entire equal-position run, making ordinary duplicate insertion stable. NaN retains XNA's non-total `CompareTo` behavior. A key can occur repeatedly and all entries retain the original reference.

`Item=` first validates the replacement. Equal Position replaces in place. A changed Position removes the old entry and calls sorted `Add`, so the replacement is repositioned; an equal-position destination lands after the existing run. Strict indexed operations reject negative indices rather than using Ruby's from-the-end indexing.

`Contains`, `IndexOf`, and `Remove` use CurveKey field equality and remove the first equal entry. `CopyTo` mutates the caller-owned Array in place and copies key references, with XNA validation order mapped to Ruby exceptions. `Clone` returns a new collection and a new backing list but shares all CurveKey references. It also retains the observable XNA cache-copy behavior: copied cached floats are marked valid even when the source cache was dirty.

Enumerators are independent, preserve collection order, and fail fast after `Add`, `RemoveAt`, `Clear`, or item replacement. A failed `Remove` and `CopyTo` do not change the backing-list version, matching `List<T>`; they therefore do not invalidate an active cursor.

## Curve state, cloning, and evaluation

A new Curve has Constant PreLoop and PostLoop, one stable empty Keys collection, and `IsConstant == true`. `IsConstant` means exactly `Keys.Count <= 1`; it does not inspect key values. `Curve.Clone` creates a new Curve and a new shallow-cloned Keys collection, copies both loop modes, and shares the contained CurveKey references.

Evaluation returns `0.0f` for no keys and the sole key's exact Value for one key, regardless of position. Segment selection is the XNA forward scan. At an ordinary key boundary, the preceding segment reaches amount 1; duplicate spans no greater than `1e-10` use amount zero. Step continuity returns the first key while `amount < 1.0f` and the second key at amount 1 (also the second key for NaN amount because that comparison is false).

Smooth segments use the exact XNA four-term cubic Hermite expression and binary32 operation order. The segment amount alone is calculated from widened double positions before narrowing to Single, as in the reference IL. Golden corpus cases distinguish this from all-double interpolation and from generic spline libraries.

## Loop formulas and negative cycles

Constant returns the exact endpoint value. Linear uses `first.Value - first.TangentIn * (first.Position - position)` before the first key and `last.Value - last.TangentOut * (last.Position - position)` after the last, so tangents are value deltas rather than position-normalized derivatives.

For Cycle, CycleOffset, and Oscillate, XNA computes a cached binary32 time range and inverse range. Its cycle calculation is `(position - first.Position) * inverseRange`; a negative result is decremented by `1.0f` before CLR truncation to Int32. This makes negative exact-cycle boundaries intentionally select the preceding cycle. Cycle wraps to the first-key interval. CycleOffset additionally adds `cycle * (last.Value - first.Value)`, preserving negative signs and binary32 order. Oscillate reverses the wrapped position when the signed cycle Int32 is odd; this is qualified for positive and negative odd/even cycles and exact boundaries.

## Tangent generation

Flat writes zero. Linear writes raw adjacent value differences: current minus previous for TangentIn and next minus current for TangentOut, with endpoint neighbor substitution. It does not divide by key spacing.

Smooth uses the previous-to-next value difference, returns zero when its absolute value is below `1.1920929e-7f`, and otherwise weights that difference by the incoming or outgoing position distance divided by the full previous-to-next position span. Endpoint substitution, singleton curves, two-key curves, nonuniform spacing, equal positions, and non-finite results are retained. The two-mode overload computes each side independently. Whole-curve forms iterate from first to last; calculations depend only on Position and Value, so earlier tangent writes do not affect later keys.

## Evidence totals

- behavior corpus: 125 PURE_XNA_DERIVED observations / 125 assertions / zero failures;
- new groups: CURVE_KEY 4, CURVE_KEY_COLLECTION 5, CURVE_EVALUATE 4, CURVE_TANGENTS 4, CURVE_LOOPS 4;
- dedicated tests: 17 runs / 174 assertions / zero failures or errors;
- generated Curve RBS: 6 types / 49 XNA member identities, with all overloads explicit and no `untyped` or catch-all signature;
- new collection mapping verifier fixtures cover wrong Item mutability, wrong enumerator return, missing generic collection interface, wrong CurveKey kind, and wrong enum value;
- native ABI inventory remains unchanged.
