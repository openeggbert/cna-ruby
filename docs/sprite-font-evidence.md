# Graphics.SpriteFont — evidence

Behaviour authority: the pinned `Microsoft.Xna.Framework.Graphics.dll` IL (SHA-256 `560080fc…`).
The fixture is MonoGame's `Default.xnb`, referenced by path through the already-configured
`CNA_TEST_XNB_DIR` and never copied into this repository.

## 1. The first candidate a BCL decision alone unblocked

`SpriteFont` carried **both** `BCL_PROJECTION` and `NATIVE_RUNTIME`. Every earlier doubly blocked
candidate — `SoundEffectInstance`, `Cue` — was resolved by building the type its IL reached. This
one was different: its il-only dependency is `SpriteBatch`, which had been **complete all along**,
so what remained really was three BCL projections.

## 2. `System.Char` is a code unit, and that decides the projection

The pinned mscorlib declares `System.Char` as a 16-bit value type: a **UTF-16 code unit**. `0xD800`
is a perfectly valid one. Ruby has no character type, and the two candidates differ in exactly that
place:

- a one-character Ruby String is a code *point* in some encoding — it cannot hold an unpaired
  surrogate, and choosing it would force an encoding decision the CLR type does not have;
- an Integer holds the code unit exactly.

The register's rule is to project what the XNA surface can reach, and the surface —
`SpriteFont.Characters`, `DefaultCharacter`, and the content pipeline's `CharReader` — can reach any
code unit. So **Integer**, and a consumer writes `font.DefaultCharacter = "*".ord`.

This lands the other side of the same line as `System.Byte[] => String`, which was decided on the
matching reasoning: a `byte[]` really *is* a byte sequence, and a Ruby String really is one.

`System.Nullable`1` is `nil`-or-value: there is no wrapper to project, because `HasValue` is
`!nil?` and `Value` is the object itself. `System.Text.StringBuilder` is a Ruby String, because a
CLR `StringBuilder` is a mutable string and a Ruby String is one — which is also what makes the two
`MeasureString` overloads collapse **exactly** rather than approximately.

## 3. `InternalMeasure`, instruction for instruction

    if (text.Length == 0) return Vector2.Zero;
    result = Vector2.Zero; result.Y = lineSpacing;
    float pendingRight = 0f; float widest = 0f; int lineBreaks = 0; bool firstOnLine = true;
    foreach code unit c:
      if (c == '\r') continue;
      if (c == '\n') {
        result.X += Max(pendingRight, 0f); pendingRight = 0f;
        widest = Max(result.X, widest);
        result = Vector2.Zero; result.Y = lineSpacing;
        firstOnLine = true; lineBreaks++; continue;
      }
      k = kerning[GetIndexForCharacter(c)];
      if (firstOnLine) k.X = Max(k.X, 0f); else result.X += spacing + pendingRight;
      result.X += k.X + k.Y;
      pendingRight = k.Z;
      result.Y = Max(result.Y, croppingData[GetIndexForCharacter(c)].Height);
      firstOnLine = false;
    result.X += Max(pendingRight, 0f);
    result.Y += lineBreaks * lineSpacing;
    result.X = Max(result.X, widest);

Two details a paraphrase loses. The **first glyph on a line clamps its left bearing to zero** instead
of paying the spacing, which is why a leading `j` does not hang off the left edge. And the height
comes from the **cropping** rectangle, not the glyph bounds.

`'\r'` is skipped outright — `ldc.i4.s 13` — so `"A\rB"` measures exactly as `"AB"`, while `"A\r\nB"`
measures as `"A\nB"`. Both are asserted.

The projection is compared with `cna_sprite_font_measure_utf8` on every measured string rather than
only with itself, and on this font the two agree everywhere: `"A"` is `(11, 21)`, `"Hello"` is
`(55, 21)`, `"Hello World"` is `(121, 21)`, and the empty string is `Vector2.Zero`.

## 4. The fallback chain

`GetIndexForCharacter` binary-searches the character map — which is why the map must be sorted, and
the test asserts that CNA answers it sorted rather than assuming it. On a miss it falls back to
`DefaultCharacter` and recurses **once**; with no default, or a default that is the character that
just missed, it raises `ArgumentException(CharacterNotInFont)`.

`set_DefaultCharacter` refuses a character the font does not define — `characterMap.Contains` —
and clearing it to `nil` is always allowed. Measured in both directions.

## 5. Two deviations

**Spacing and NaN.** `set_LineSpacing` and `set_Spacing` are four IL instructions each: bare field
writes with no validation at all, so XNA stores a negative line spacing and a `NaN` spacing without
complaint. `cna_sprite_font_set_spacing` documents "must be finite" and answers
`CNA_RESULT_INVALID_ARGUMENT`. There is no managed rule to reproduce, so nothing is invented: the
negative line spacing is stored exactly as XNA stores it, and CNA's refusal of `NaN` surfaces as
`CNA::NativeError`.

**Ownership.** XNA's `SpriteFont` is **not** `IDisposable` — its contract declares no `Dispose` and
no interface. The `ContentManager` records the `Texture2D` its reader built and disposes that on
`Unload`, leaving the font object alive with a dead atlas. CNA hands back **two** owned handles,
the font and its atlas texture, and no projected `Texture2D` to record. So the font owns both and
releases both, and the manager triggers that because it records anything answering `Dispose` and
`CNA::Runtime::NativeResource` gives this type one. The widening is that a consumer can call
`font.Dispose`, which XNA does not offer; the safety is that a font whose atlas is gone reports
`IsDisposed` rather than being silently unusable. `SpriteFont` still declares no `Dispose` identity
of its own, which the test asserts.

## 6. What is not claimed

Nothing is drawn. `SpriteBatch.DrawString` is not added, so this font measures text and nothing
renders it. `cna_sprite_font_create` is deliberately unbound: XNA gives a consumer no constructor,
so the content manager is the only producer and a create route would be an identity XNA does not
have.
