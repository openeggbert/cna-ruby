# `Media.VideoPlayer`: the eleventh `NATIVE_RUNTIME` that was not one

The last unaudited candidate on the dependency frontier, and the one most likely to have been right:
fifteen of its members are native-reachable in the pinned IL, including the constructor,
`GetTexture` and every transport control.

It was measured, not assumed. The blocker is wrong again.

## What the header threatened

`cna_video_create` documents `CNA_RESULT_NOT_SUPPORTED` **"when CNA was built without its optional
video decoder"** — the same shape as the audio finding Native frontier 4 recorded and Native
frontier 5 explained (`CNA_AUDIO_PLATFORM=NULL`, a build-time choice). So the first question was
whether the qualified 0.21.0 artifact carries the decoder at all.

## What was measured

`build-probe/videoplayer.c`, at the C ABI with no Ruby in the path, `CNA_GRAPHICS_RENDERER=HEADLESS`:

    cna_video_player_create           -> SUCCESS
    get_is_disposed                   -> SUCCESS  false
    get_state                         -> SUCCESS  0  (CNA_MEDIA_STATE_STOPPED)
    get_volume                        -> SUCCESS  1.0
    set_volume(0.25) / get_volume     -> SUCCESS  0.25
    get_is_looped / set / get         -> SUCCESS  false -> true
    get_is_muted                      -> SUCCESS  false
    get_play_position_ticks           -> SUCCESS  0
    get_video                         -> SUCCESS  available=0
    get_texture (no video)            -> SUCCESS  available=0
    stop (already stopped)            -> SUCCESS
    pause (stopped)                   -> SUCCESS
    dispose / get_is_disposed         -> SUCCESS  true

Every one of the fifteen contract members has a canonical route, and every route works headless with
no video at all.

**The decoder is compiled in.** Against a real AVI that already exists on this host —
`planetblupi/movie/play101.avi`, referenced by path and never copied into this repository, exactly
as the XACT and XNB fixtures are:

    cna_video_create(real file)  -> SUCCESS   probed 320x240, fps 12.048193, duration 65570000 ticks
    cna_video_player_play        -> SUCCESS
    get_state after play         -> 1         (CNA_MEDIA_STATE_PLAYING)
    get_texture                  -> SUCCESS   available=1

A real file is probed for its real metadata, playing moves the state machine to `Playing`, and a
frame texture exists. That is not a stub.

## The one thing that does fail, and why it is not a failure

    cna_video_create(missing path)          -> IO       "Could not find file '…'"
    cna_video_create_with_metadata(missing) -> SUCCESS   declared 320x240
    cna_video_player_play(that video)       -> SUCCESS
    get_state after play                    -> 0        (still Stopped)

`create_with_metadata` is the compiled-asset constructor and the header says plainly that it does
not touch the file. Handing the player a video whose file does not exist therefore reports `SUCCESS`
from `Play` and leaves the state at `Stopped`. That is CNA reporting the canonical constructor's
behaviour faithfully, not a broken route — and it is the reason the audit used a real file rather
than fabricated metadata to answer the decoder question.

## The real blocker, which is a producer

`VideoPlayer.Play` takes a `Media.Video`. XNA's only producer for one is
`ContentManager.Load<Video>`; **CNA exports no content route for video** — the eight
`cna_content_manager_load_*` routes cover effects, models, sound effects, sprite fonts, textures and
cubes, and nothing else. `Media.Video`'s own projection has been producerless since Foundation 52
for exactly this reason, and completing it recorded that.

So the honest statement is narrow and specific:

- `NATIVE_RUNTIME` is **wrong** for this type, the eleventh time this register has retired that
  word. The routes exist, execute and behave.
- Fourteen of the fifteen members are fully reachable from Ruby.
- `Play` is reachable, correct, and cannot be handed a legal argument by a consumer of this
  binding — because nothing here produces a `Video`. That is `Media.Video`'s deferral, not
  `VideoPlayer`'s, and building this type does not fabricate a way around it.

## What is deliberately not claimed

No assertion is made about anything visible. `HEADLESS` qualifies execution and command submission,
not rendered output, and the audit measures that a frame texture *exists* rather than what is in it.
No video fixture was created, converted or copied; the file used is one that was already on this
machine, and it is referenced by an environment variable path like every other fixture in this
project.
