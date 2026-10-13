# README media

What is in this folder, how it is produced, and the one piece of it that still needs a
human with a screen recorder.

| File | What it is | Produced by |
|---|---|---|
| `demo.gif` | The animated graph in the README | `tools/gif/make-gif.mjs` — headless, no screen capture |
| `icon.png` | The 256 px mark used for the Gallery listing and social previews | `tools/icon/New-IntuneGraphIcon.ps1` |

## `demo.gif` is rendered, not recorded

`tools/gif/make-gif.mjs` re-implements the force-directed layout and the palette of the
HTML viewer against `@napi-rs/canvas`, then encodes with `gifenc`. No browser, no
`ffmpeg`, no capture — which is why the output is reproducible and why the file is
900 × 500 and about 1.6 MB rather than the 8 MB a screen capture of the same thing
costs.

```bash
cd tools/gif
npm install
Export-IntuneGraph -DemoData -Path tools/gif/graph.json   # from the repo root, pwsh
npm run build                                             # -> ../../docs/img/demo.gif
```

`tools/gif/graph.json` is gitignored on purpose: it is a generated export, and the
recorder is the only thing that reads it. Regenerate it whenever the demo dataset
changes, or the GIF will keep showing the graph the dataset used to be.

The animation is four phases over a **6,520 ms** loop, and the order matters:

| Phase | Frames | Starts at | Lasts |
|---|---|---|---|
| 1 — Settle | 34 × 70 ms | 0 ms | 2,380 ms |
| 2 — Hold | 6 × 90 ms | 2,380 ms | 540 ms |
| 3 — Explain `SG-Finance` | 2 × 60 + 10 × 120 ms | 2,920 ms | 1,320 ms |
| 3 — Explain `LOB Finance App` | 2 × 60 + 10 × 120 ms | 4,240 ms | 1,320 ms |
| 4 — Return to full view | 8 × 120 ms | 5,560 ms | 960 ms |
| | **72 frames** | | **6,520 ms** |

1. **Settle** — the layout relaxes while the camera eases to fit.
2. **Hold** — six frames on the settled graph, so it reads as a shape before anything
   moves again.
3. **Explain** — one beat each on `SG-Finance` and `LOB Finance App`, dimming everything
   outside the node's neighbourhood. This is the only part that shows the product's
   actual claim: a solid green edge for the include, a red dashed one for the exclude,
   and the group path between them.
4. **Return to full view** — back to the undimmed graph, and the **loop point**: the last
   frame here cuts straight to the first frame of the settle. A replacement capture has
   to end somewhere it can cut back to its own opening, which is what makes this beat
   worth listing rather than trimming.

The offsets above come from the four runs of `push()` in `make-gif.mjs`. Do not take them
from the source alone — the committed blob is what the README serves, and #12 is an open
case of the two having drifted apart. Read the delays back out of the file itself:

```bash
python3 - <<'EOF'
d = open('docs/img/demo.gif', 'rb').read()
i, delays, flags = 13, [], d[10]
if flags & 0x80: i = 13 + 3 * 2 ** ((flags & 7) + 1)
while i < len(d):
    if d[i] == 0x21 and d[i+1] == 0xF9:          # Graphic Control Extension
        delays.append(d[i+4] | d[i+5] << 8); i += 8
    elif d[i] == 0x21:                            # other extension
        i += 2
        while d[i]: i += d[i] + 1
        i += 1
    elif d[i] == 0x2C:                            # image descriptor
        lf = d[i+9]; i += 10
        if lf & 0x80: i += 3 * 2 ** ((lf & 7) + 1)
        i += 1
        while d[i]: i += d[i] + 1
        i += 1
    elif d[i] == 0x3B: break
    else: i += 1
cs = [x * 10 for x in delays]
runs = []
for v in cs:
    if runs and runs[-1][1] == v: runs[-1][0] += 1
    else: runs.append([1, v])
print('frames', len(cs), '| loop', sum(cs), 'ms |', [tuple(r) for r in runs])
EOF
```

which prints, for the file committed today:

```text
frames 72 | loop 6520 ms | [(34, 70), (6, 90), (2, 60), (10, 120), (2, 60), (18, 120)]
```

Six runs for five beats, because the two `120 ms` stretches merge: the ten tail frames of
the second explain beat and the eight return frames share a delay. Everything else matches
the table exactly. Run this rather than editing the numbers by hand whenever the recorder
changes — it reads the artefact, so it catches a recorder and a committed file that no
longer agree, which is #12's failure mode in the timing dimension instead of the branding
one.

### Known defect: the committed GIF and the recorder disagree

The GIF in the repository today reads **"Contoso demo tenant · 41 nodes · 34 edges"** in
its header. `make-gif.mjs` writes **"Silver Chariot Corporate"**, which is the
`tenantName` in `src/IntuneGraphKit/DemoData/manifest.json`. The committed file
therefore predates the rename, and re-running the recorder today changes the branding in
the README without anyone intending it. Do not regenerate `demo.gif` as a side effect of
an unrelated change — settle the name first.

## The recording that is still missing

The explain beat is the valuable part of the loop, and it arrives **2.92 s** in — so a
visitor giving the README eight seconds sees it twice over, and waiting for it is not the
complaint. What that visitor also sees is the settle: **2,380 ms, 36% of a 6,520 ms
loop**, spent on the one beat this page itself says says nothing.

That is a narrower problem than a late payoff, and it has two fixes of very different
cost. The choice is worth making on the figures rather than by default:

- **Trim the settle — cheap, no recorder.** Drop the first loop in `make-gif.mjs` from 34
  frames to around ten and the explain beat lands inside the first second. What it costs
  is legibility: the settle is what makes the layout read *as* a layout rather than as a
  graph that was always that shape, and ten frames at 70 ms is 700 ms to carry that. It
  may not be enough. Try it and look before committing to it.
- **Capture the real viewer — expensive, needs Juan.** A render cannot show the search
  box being typed into or a side panel opening, and that is the part a visitor can imagine
  themselves doing. This is the stronger fix and the only one that adds anything new.

They are not exclusive, and neither is blocked on the other. The capture is specified
below and is still wanted; the trim is a half-hour experiment that would improve the
existing GIF whether or not the capture ever happens.

**This needs Juan — it cannot be automated.** Spec for the capture:

| Constraint | Value | Why |
|---|---|---|
| Length | 10–15 s, seamless loop | Past 15 s nobody waits for the loop point |
| Dimensions | 1280 × 720 captured, downscaled to 900 px wide | Matches `demo.gif`, so the two sit together |
| Frame rate | 12–15 fps | Enough for cursor motion; 24 fps doubles the file for nothing |
| Size | **under 5 MB**, hard | GitHub serves it on every README view |
| Format | GIF, or MP4 in a `<video>` tag if it will not fit | GitHub renders `<video>` in READMEs |
| Chrome | Browser window only, no desktop, no tab bar, no bookmarks | Anything identifying is a leak and a distraction |
| Tenant | `-DemoData` only, **never** a real tenant | Device names, UPNs and group names are all tenant data |

Storyboard — four beats, no narration, no cuts:

1. **0–2 s** The graph, already settled. Do not record the settle; it is what the
   existing GIF already shows and it says nothing.
2. **2–6 s** Type `Finance` into the search box. The graph filters live. This is the
   first thing a viewer can imagine themselves doing.
3. **6–11 s** Click **LOB Finance App**. The side panel opens with the node's type,
   properties and its incoming and outgoing edges — `SG-Finance` including it,
   `SG-Contractors` excluded. Pause long enough to read the panel.
4. **11–14 s** Click **Reset view**, returning to the full graph. That is the loop point.

Record with ShareX or ScreenToGif on Windows. If the result is over 5 MB, drop to 12 fps
and trim the tail before touching the dimensions — resolution is what makes the side
panel readable, and an unreadable side panel makes beat 3 pointless.

### Where it goes, exactly

Directly under the badge block in `README.md`, above the `> Intune assignments *are* a
graph` pull-quote — so it lands in the first screenful on a laptop:

```markdown
![Filtering the IntuneGraph viewer to Finance, then opening LOB Finance App to see SG-Finance including it and SG-Contractors excluded](docs/img/viewer.gif)
```

Alt text carries the whole story, because it is what a screen-reader user and anyone on
a throttled connection gets instead of the animation. "Demo" is not alt text.

If it ends up as MP4:

```markdown
<video src="docs/img/viewer.mp4" autoplay loop muted playsinline width="900"></video>
```

Leave the existing `![...](docs/img/demo.gif)` where it is, under **One HTML file, zero
network calls** — it illustrates that section honestly.

## Adding any other image

- Put it here, in `docs/img/`. Reference it with a repository-relative path so it works
  on GitHub, on the Gallery listing and in a local Markdown preview alike.
- Alt text describes what the image shows, not that it is an image.
- Declare the extension `binary` in [`.gitattributes`](../../.gitattributes) before the
  first file of that type is committed. `*.png`, `*.jpg`, `*.gif` and `*.mp4` are already
  there. Without an entry the repository-wide `* text=auto eol=lf` is free to treat the
  file as text and strip its CR bytes on commit, and no image or video format checksums
  its own payload — the result is a silently corrupt frame, not an error.
- Nothing captured from a real tenant, ever — not a device name, not a UPN, not a group
  name. `-DemoData` produces a graph rich enough for any screenshot this project needs.
