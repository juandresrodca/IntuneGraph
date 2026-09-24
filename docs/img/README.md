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

The animation is three phases, and the order matters:

1. **Settle** — 34 frames at 70 ms while the layout relaxes, camera easing to fit.
2. **Hold** — 6 frames on the settled graph.
3. **Explain** — 12 frames each on `SG-Finance` and `LOB Finance App`, dimming
   everything outside the node's neighbourhood. This is the only part that shows the
   product's actual claim: a solid green edge for the include, a red dashed one for the
   exclude, and the group path between them.

### Known defect: the committed GIF and the recorder disagree

The GIF in the repository today reads **"Contoso demo tenant · 41 nodes · 34 edges"** in
its header. `make-gif.mjs` writes **"Silver Chariot Corporate"**, which is the
`tenantName` in `src/IntuneGraphKit/DemoData/manifest.json`. The committed file
therefore predates the rename, and re-running the recorder today changes the branding in
the README without anyone intending it. Do not regenerate `demo.gif` as a side effect of
an unrelated change — settle the name first.

## The recording that is still missing

Phase 3 is the valuable second of the whole loop, and it arrives 4.5 seconds in. A
visitor who looks at the README for eight seconds sees a graph jiggling. The fix is not
a better render; it is a short screen capture of the real viewer being *used*, placed in
the first screenful, with the rendered GIF kept lower down where it already sits.

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
- Nothing captured from a real tenant, ever — not a device name, not a UPN, not a group
  name. `-DemoData` produces a graph rich enough for any screenshot this project needs.
