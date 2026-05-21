---
name: cinematic-video-prompt-engineer
description: >
  Transforms ordinary text prompts into richly detailed, cinematically precise AI video
  generation prompts. Use this skill whenever the user wants to generate an AI video
  and provides a prompt — even a casual one — or asks to "improve", "enhance", "make
  cinematic", or "polish" a video prompt. Also triggers when users describe a scene,
  mood, or story beat and want it turned into a video. The skill applies professional
  cinematography language — shot type, lens, lighting, camera movement, color palette,
  visual texture, and editing rhythm — to elevate vague descriptions into production-
  quality prompts for tools like Sora, Runway, Kling, Pika, or Hailuo.
  ALWAYS use this skill when the user mentions AI video, video generation, or video prompts.
---

# Cinematic Video Prompt Engineer

A skill for upgrading plain video descriptions into film-language-rich prompts that
consistently produce higher-quality, more intentional AI video outputs.

---

## Theoretical Foundation

This skill synthesizes lessons from *Cinematography: Theory and Practice* (Blain Brown,
4th ed.) and the broader canon of visual storytelling craft. The core insight: AI video
models respond to the same visual language that cinematographers use to communicate with
directors and crew. When you name the lens, light, and camera move, the model has fewer
creative gaps to fill randomly.

### The Seven Pillars of Cinematic Prompting

Derived from Brown's conceptual tools of visual storytelling:

| Pillar | What it controls | Why it matters in AI video |
|--------|-----------------|---------------------------|
| **Frame / Shot Type** | How much of the scene we see | Determines emotional scale and intimacy |
| **Lens Language** | Spatial compression or expansion | Wide lenses distort/expand; long lenses compress and isolate |
| **Lighting** | Mood, texture, time-of-day, emotion | The single biggest lever on "feel" |
| **Color Palette** | Tone, era, emotional register | Warm/cool, saturated/desaturated, contrast |
| **Camera Movement** | Energy, tension, revelation | Static = authority; handheld = chaos; dolly-in = significance |
| **Visual Texture** | Surface quality, era, treatment | Film grain, fog, diffusion, practical lights |
| **Editing Rhythm** | Pacing, time, emphasis | Slow build vs. rapid cuts; implied in single-shot prompts via motion |

---

## The Prompt Optimization Process

### Step 1 — Parse the Input Prompt

Read the user's prompt and identify what is present vs. absent across all Seven Pillars.
Build a mental checklist:

```
[ ] Subject / Action      — who/what is doing what
[ ] Shot Type             — wide, medium, close-up, etc.
[ ] Lens Focal Length     — 14mm, 35mm, 85mm, 200mm
[ ] Camera Movement       — static, dolly, handheld, crane, Steadicam
[ ] Lighting Setup        — key direction, quality (hard/soft), color temp
[ ] Color Palette / Grade — warm/cool, saturation, contrast, LUT style
[ ] Visual Texture        — grain, fog, practical lights, diffusion filters
[ ] Depth of Field        — shallow / deep, subject isolation
[ ] Time of Day / Weather — magic hour, overcast, night, rain
[ ] Aspect Ratio / Format — 2.39:1 cinematic, 16:9, vertical
[ ] Mood / Genre Tone     — noir, documentary realism, dreamlike, hyper-real
```

Missing items = opportunities to enrich. Do not override what the user specified.

### Step 2 — Infer Intent and Genre

Derive the emotional and narrative register from the user's words:
- Action words ("chase", "escape") → handheld, telephoto, fast movement
- Intimate words ("whisper", "grief") → close-up, soft diffused light, shallow DOF
- Epic words ("vast", "ancient", "battle") → wide establishing, crane moves, deep focus
- Sinister words ("shadow", "dread") → low-key chiaroscuro, upstage or practical lighting
- Nostalgic words ("memory", "childhood") → warm palette, slight desaturation, 35mm grain

### Step 3 — Apply the Enrichment Rules

#### SHOT TYPES (pick one main + optional secondary)
```
Extreme Wide Shot (EWS)   — subject tiny in landscape; conveys isolation, scale
Wide Shot (WS)            — full body + environment; establishes geography
Medium Shot (MS)          — waist up; conversational, neutral
Medium Close-Up (MCU)     — chest up; the workhorse of character shots
Close-Up (CU)             — face fills frame; emotion, intensity
Extreme Close-Up (ECU)    — single feature (eye, hand); detail, menace, fragility
Over-the-Shoulder (OTS)   — POV relationship; detective gaze, intimacy
Two-Shot                  — two subjects; relationship, power dynamic
Insert / Detail Shot      — object detail; Hitchcock's glowing milk glass
```

#### LENS FOCAL LENGTHS
```
Ultra-Wide 8-18mm    — spatial distortion, comedy or horror, face warp
Wide 24-28mm         — environmental storytelling, slight expansion
Normal 35-50mm       — closest to human eye, naturalistic, invisible
Portrait 85mm        — gentle compression, flattering, standard drama
Short Tele 100-135mm — moderate compression, clean separation
Long Tele 200-400mm  — heavy compression, isolation, desert mirage effect
                       (e.g., Lawrence of Arabia's entrance shot)
```

#### CAMERA MOVEMENTS
```
Static / Locked Off    — authority, observation, formalism (Kubrick's Shining corridors)
Pan                    — follows action horizontally; reveals relationships
Tilt                   — reveals vertical scale (buildings, power)
Dolly In               — signifies importance, intimacy, threat (Hitchcock push-in)
Dolly Out / Pull Back  — reveals context, isolation (High Noon crane-back)
Tracking / Follow      — character agency, momentum
Handheld               — chaos, documentary realism, subjective anxiety
Steadicam              — fluid, ghostly, omniscient (The Shining hallways)
Crane / Jib Up         — god's eye view, revelation, scale
Drone Aerial           — landscape scale, modern epic feel
Whip Pan               — energy, disorientation, time jump
```

#### LIGHTING SETUPS
```
High-Key              — bright, fill-heavy, low contrast; comedy, daytime safety
Low-Key               — dark, contrasty, deep shadows; noir, drama, menace
Chiaroscuro           — extreme light/dark split; Apocalypse Now's Kurtz
Rembrandt             — triangular highlight on shadow side of face; classic portraiture
Motivated / Practical — light sources visible in frame (lamps, candles, screens)
Upstage / Reverse Key — key light from behind and to side; separation, mystery
Backlight / Kicker    — rim around subject; separation from background, halo
Magic Hour            — golden 20-min window after sunset; warm, directional, romantic
Overcast / Diffused   — flat natural light; documentary realism, intimacy
Hard Light            — defined shadows, texture, heat; desert, conflict
Soft Light            — wrapping, flattering; emotional scenes, interiors
Practical Neon        — colored urban night; alienation, modernity (Black Rain's Osaka)
Moonlight Effect      — blue-toned, low level, cool shadows
```

#### COLOR PALETTES (reference established film palettes)
```
Teal-and-Orange       — modern blockbuster; high contrast complementary
Desaturated / Bleach  — gritty realism, war, poverty (Saving Private Ryan)
Warm Golden           — nostalgia, safety, romance, magic hour
Cool Blue             — isolation, night, corporate coldness
Monochromatic Green   — surveillance, hacker, military night-vision
High Saturation       — fairy tale, Wes Anderson symmetry, retro vibrancy
Black and White       — timeless, memory, artistic gravity
Split-Tone            — shadows one color, highlights another (e.g., teal shadows / amber highlights)
```

#### VISUAL TEXTURE ELEMENTS
```
Film Grain            — 16mm or 35mm grain overlay; organic, nostalgic
Anamorphic Lens Flare — horizontal streak flares; cinematic, epic
Shallow DOF Bokeh     — out-of-focus background circles; subject isolation
Atmospheric Haze      — smoke, fog, practical atmosphere; depth, mystery
Rain / Wet Pavement   — reflections, isolation, urban mood
Lens Diffusion        — softening filter (Pro-Mist, Black Satin); dreamlike
Dust Motes / Particles — shafts of light, aged space, warm intimacy
Practical Fire / Candle — warm flickering key; intimacy or menace
```

### Step 4 — Assemble the Enriched Prompt

Use this structural template:

```
[SHOT TYPE + LENS FOCAL LENGTH], [CAMERA MOVEMENT if any],
[SUBJECT + ACTION], [ENVIRONMENT / LOCATION],
[LIGHTING SETUP + DIRECTION + QUALITY],
[COLOR PALETTE + GRADE STYLE],
[VISUAL TEXTURE ELEMENTS],
[MOOD / ATMOSPHERE in 1-2 words],
[OPTIONAL: aspect ratio, frame rate, film stock reference]
```

**The output must read as a single coherent description, not a list.**
Weave the technical elements into natural film-language sentences.

---

## Enrichment Rules (Non-Negotiable)

1. **Preserve Intent** — never change the subject, action, or story of the user's prompt.
2. **One Dominant Shot** — choose the single most powerful shot type; do not list multiple.
3. **Motivated Choices** — every added element must serve the emotion. Ask: does this lens / light / movement reinforce what the scene is *about*?
4. **Specificity over Generality** — "85mm lens, soft window light, shallow depth of field" beats "cinematic close-up shot."
5. **No Studio Jargon Overload** — the enriched prompt should still be readable and evocative, not a gear checklist.
6. **Color Palette Last** — specify color/grade at the end so it acts as an emotional seal on the whole image.
7. **Atmospheric Texture is Optional but Powerful** — grain, haze, or flare can add enormous character; use when the mood supports it.

---

## Quick-Reference: Emotion → Cinematic Recipe

| Emotion / Tone | Shot | Lens | Movement | Light | Color |
|---------------|------|------|----------|-------|-------|
| Loneliness / Isolation | EWS or CU | 200mm (compression) or 14mm (emptiness) | Slow dolly out | Motivated practical, low-key | Desaturated cool blue |
| Intimacy / Love | MCU or CU | 85mm | Static or imperceptible dolly-in | Soft, warm window light | Warm golden, slight desaturation |
| Menace / Dread | ECU or Low-angle WS | 28mm wide distortion | Static or slow creep | Chiaroscuro, upstage key | Teal-shadow, desaturated |
| Power / Authority | Low-angle MS | 35mm | Static, locked off | Hard directional key | High contrast, neutral |
| Chaos / Action | MS or WS | 35mm | Handheld, whip pans | Motivated mixed sources | Teal-and-orange, high contrast |
| Wonder / Epic Scale | EWS | 24mm | Slow crane rise or drone pull-back | Magic hour, directional | Warm-to-cool gradient sky |
| Memory / Nostalgia | MCU | 50mm | Slow Steadicam drift | Soft, diffused, warm | Warm, desaturated, 16mm grain |
| Urban Alienation | MS or WS | 35mm | Static or tracking | Practical neon, wet pavement | Cool, magenta-shifted, saturated |

---

## Before / After Examples

### Example 1 — Minimal Input

**User prompt:**
> "A woman walking alone at night in the rain."

**Enriched prompt:**
> Medium shot, 50mm lens, locked-off static frame. A woman walks slowly through a rain-slicked city street at night, alone, her reflection fractured in the wet pavement below her. Motivated neon signage casts shifting pools of magenta and cyan across her face — the only light source. Rain falls through the practical light beams, each drop briefly visible. The background is a shallow-focus blur of smeared neon bokeh. Desaturated color grade with cool teal shadows and warm amber skin tones. Atmospheric haze and light film grain. Mood: quiet desolation.

---

### Example 2 — Action / Tension

**User prompt:**
> "A man running through a crowd trying to escape."

**Enriched prompt:**
> Handheld medium shot, 35mm lens, tight and unstable, pushing urgently through the crowd from behind the subject. A man shoves through a packed urban market, his face glimpsed in fractured cuts between bodies and stalls. Hard midday sunlight creates sharp shadow cuts across faces. The camera jostles and corrects, barely keeping him in frame — the instability is the story. Teal-and-orange color grade, high contrast. Fast motion with occasional rack focus from foreground obstructions to the fleeing figure. No music — only crowd noise, footsteps, impact. Mood: visceral desperation.

---

### Example 3 — Emotional / Intimate

**User prompt:**
> "Old man sitting by a window, looking outside."

**Enriched prompt:**
> Close-up, 85mm lens, shallow depth of field. An elderly man sits near a large window, face turned toward soft overcast daylight that wraps gently across his cheekbone and brow — the only light source, coming from frame-left. His eyes are still; the slight out-of-focus movement of leaves beyond the glass suggests time passing. The camera is static, respectful, unhurried. Warm desaturated color grade — faded like an old photograph. Slight 35mm film grain. The background bokeh is muted green. His hands rest loosely in his lap, barely in frame. Mood: quiet contemplation, unspoken grief.

---

### Example 4 — Epic / Landscape

**User prompt:**
> "A warrior standing on a cliff at sunrise."

**Enriched prompt:**
> Extreme wide shot, 24mm lens, slow crane rise from near ground level up to eye-height. A lone warrior stands at the edge of a vast sea cliff, silhouetted against a burning amber-gold horizon as the sun crests the distant water. Magic hour light rakes across the landscape at a flat angle, cutting hard shadows from every rock and crevice. The figure is small against the immensity of sky and ocean — scale as meaning. Camera rises slowly as the horizon brightens. Color palette: deep orange sky bleeding into violet upper atmosphere, dark foreground underexposed for silhouette contrast. Anamorphic lens flare as the sun edge appears. Film-out look, 2.39:1 aspect ratio. Mood: solitary resolve.

---

### Example 5 — Horror / Dread

**User prompt:**
> "Something moving in the dark hallway."

**Enriched prompt:**
> Static locked-off wide shot, 28mm lens at low height — just above floor level, looking down an impossibly long hallway. One-point perspective pulls the eye to a vanishing point at the far end. The only illumination comes from a single practical overhead fluorescent that flickers weakly, casting hard shadows down the corridor walls. In the far distance, something shifts — barely visible, ambiguous, never clearly human. No camera movement. The stillness is the dread. Color grade: desaturated green-gray with crushed blacks. No film grain — digital cleanliness makes it feel more real and more wrong. Mood: slow creeping wrongness.

---

## Prompt Templates by Use Case

### Template A — Narrative Drama Scene
```
[SHOT TYPE], [FOCAL LENGTH] lens, [CAMERA MOVEMENT or "static"].
[CHARACTER(S)] [ACTION] in [LOCATION / ENVIRONMENT].
[LIGHTING DESCRIPTION: direction, quality, source, color temperature].
[COLOR PALETTE / GRADE].
[TEXTURE ELEMENTS if any].
[DEPTH OF FIELD note].
Mood: [1-2 words].
```

### Template B — Landscape / Establishing
```
[SHOT TYPE] aerial / crane shot, [FOCAL LENGTH] lens.
[LANDSCAPE / ENVIRONMENT DESCRIPTION].
[TIME OF DAY + WEATHER + LIGHT QUALITY].
[CAMERA MOVEMENT: slow push, drift, rise].
[COLOR PALETTE: sky, land, horizon].
[ATMOSPHERIC TEXTURE: haze, mist, heat shimmer].
[SCALE REFERENCE if helpful].
```

### Template C — Action / Kinetic
```
Handheld [SHOT TYPE], [FOCAL LENGTH] lens.
[CHARACTER] [URGENT ACTION] through [ENVIRONMENT].
[LIGHTING: practical motivated sources, hard/fast].
High energy camera — jostling, reframing, barely keeping up.
[COLOR GRADE: high contrast, teal-and-orange or desaturated].
[SOUND DESIGN note if useful for rhythm].
Mood: [urgency word].
```

### Template D — Horror / Tension
```
Static [SHOT TYPE], [FOCAL LENGTH] — [LOW or HIGH angle].
[ENVIRONMENT: architecture, light sources, emptiness].
[ONE ELEMENT of wrongness — subtle, unexplained].
[LIGHTING: minimal, motivated, flickering or hard].
Long take — no cuts. The waiting is the horror.
[COLOR GRADE: desaturated, crushed blacks, cool or sickly green].
Mood: [dread word].
```

---

## Filmmaker Reference Library

Use these as touchstones when mapping user intent to visual language:

| Visual Goal | Reference Film | Key Technique |
|------------|---------------|---------------|
| Isolation in landscape | *Lawrence of Arabia* | 500mm lens, heat mirage compression |
| Supernatural menace | *The Shining* | One-point perspective, Steadicam |
| Urban alienation | *Blade Runner 2049* | Upstage lighting, shallow focus, haze |
| Gritty realism | *Children of Men* | Long handheld takes, available light |
| Epic military scale | *Dunkirk* | Static wide frames, diegetic sound |
| Intimate memory | *The Tree of Life* | 35mm grain, natural light, whisper DOF |
| Noir dread | *Chinatown* | Detective POV, OTS, hard practical light |
| Visceral chaos | *Saving Private Ryan* | Handheld, desaturated, skip-bleach process |
| Dreamlike wonder | *Pan's Labyrinth* | Warm amber practicals, shallow focus, dust motes |
| Cold corporate threat | *Zodiac* | Flat overcast, wide angle, sterile locations |

---

## How Claude Should Use This Skill

1. **Read** the user's prompt completely.
2. **Run the Seven-Pillar checklist** — identify what's present and what's absent.
3. **Infer the genre and emotion** from the user's language choices.
4. **Select motivated cinematic choices** from the enrichment rules — do not apply everything, choose what serves the scene.
5. **Write the enriched prompt** using the appropriate template as a structural scaffold, but outputting natural, evocative language — not a checklist.
6. **Show before/after** so the user understands what was added and why.
7. **Optionally explain** the key cinematic choices made (shot type rationale, lighting logic) in 2-3 sentences.

### Output Format

```
## 🎬 Enriched Prompt

[Full enriched prompt — 3-8 sentences of natural film language]

---

## 🔍 What Was Added

- **Shot / Lens:** [choice + 1-line rationale]
- **Camera Movement:** [choice + rationale]
- **Lighting:** [setup + rationale]
- **Color Palette:** [palette + rationale]
- **Texture:** [element + rationale if used]
```

---

## Edge Cases

- **User specifies some cinematic details** → respect them fully, only fill in the gaps.
- **Abstract / metaphorical prompt** → lean into visual metaphor (Memento's Polaroid technique); find a concrete visual representation of the abstraction.
- **Comedy genre** → follow Brown's rule: wider shots, fewer close-ups, flatter lighting, higher key. Comedy lives in the wide shot.
- **Music video** → prioritize color palette, texture, and rhythm over narrative logic; multiple looks are acceptable.
- **Product / commercial** → table-top macro lighting, clean backgrounds, controlled DOF; reference practical motivated sources.
- **Vertical / social format** → note 9:16 aspect ratio, reframe compositional rules for vertical (headroom above, action in center third).
