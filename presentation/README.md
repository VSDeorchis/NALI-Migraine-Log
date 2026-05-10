# Clinical overview deck

A short slide deck (3 slides, 16:9) for presenting NALI Migraine Log
("Headway") to a clinical audience.

## Files

- **`NALI_Migraine_Log_Clinical_Overview.pptx`** — the deck. Open in
  PowerPoint, Keynote, or Google Slides.
- **`build_deck.py`** — the source of truth. Re-run to rebuild the
  `.pptx` after edits.

## Slide outline

1. **Title / Pitch** — what NALI Migraine Log is, the three-platform
   reach (iPhone / Apple Watch / Mac), and three quick credibility
   stats (test count, third-party SDKs, supported platforms).
2. **What it captures & how it predicts** — two-column card layout
   covering the clinical data captured (events, triggers, meds, life
   impact, Apple Health, weather, voice/Watch entry) and the
   analytics + on-device risk-prediction surface.
3. **Privacy by design + clinical relevance** — three privacy
   pillars (on-device + iCloud, no SDKs, two-way Apple Health) and
   six concrete bedside use cases (better history, trigger ID,
   medication-overuse signal, hormonal workup, prodromal awareness,
   treatment response).

## Rebuilding

```sh
python3 -m pip install python-pptx
python3 build_deck.py
```

## Speaker-note crib (~5 min)

- **Slide 1 (60 s).** Frame the problem — patients show up with vague
  diaries; we want structured, longitudinal data without the privacy
  baggage of a typical health app. Emphasize that there are no
  developer-side servers and no third-party SDKs.
- **Slide 2 (2 min).** Walk the left column (data captured) once,
  then the right column (analytics) once. Anchor on the HealthKit
  correlations and the 24-hour risk forecast as the most clinically
  novel pieces.
- **Slide 3 (2 min).** Close on privacy + the six clinical
  use-cases. The bottom strip is the takeaway: free, no account,
  works offline, three Apple platforms.
