# Known Android Reference Fixes

This document records confirmed behavior that takes precedence over the Android reference snapshot. Add future fixes as separate sections using the same **Android reference bug** and **Correct intended behavior** structure.

## Plus English learning-language initialization

**Android reference bug:** A fresh plus-english-only installation with an English UI can initialize Hebrew as the learned language while the learning-language selector is hidden.

**Correct intended behavior:**

- Minik Plus English always learns English.
- Hebrew is never a valid learned-language state for this product.
- Stored Hebrew learning-language state must not be restored for this product.

The iOS implementation must not copy the Android bug.

## Dehumidifier vocabulary artwork

**Android reference bug:** The production `dehumidifier.webp` resembles a pump
bottle or liquid dispenser and does not communicate a household dehumidifier.

**Correct intended behavior:** The iOS vocabulary image shows a recognizable
upright dehumidifier with an air-intake grille and a distinct removable water
reservoir. It must not use humidifier mist, bottle, dispenser, or generic air
purifier imagery.

## Helix vocabulary artwork

**Android reference bug:** The production `helix.webp` depicts a film reel with
loose film instead of a geometric helix.

**Correct intended behavior:** The iOS vocabulary image shows one continuous
three-dimensional coil making repeated turns around an invisible axis. It must
not depict film, a flat spiral, a DNA double helix, or a spring attached to
another object.

## Grown-up check before the Parent Area (iOS only)

**Android reference behavior:** In Minik Plus, Minik Plus English and Minik Math Plus,
the Parent Area button opens the Parent Area directly. Android asks the grown-up
question only before purchases and links.

**Correct intended behavior (owner, 2 November 2026):**

- On iOS the Parent Area button first shows the grown-up check (`ParentalGateView`,
  presented by `MinikActivityHubView`); the Parent Area opens only after it is solved.
- This is why the App Store age rating answers **Parental Controls: Yes** for these
  apps. Removing the gate would make that answer untrue.
- Android is deliberately left unchanged. When porting Android changes to iOS, do not
  remove this gate to "match Android".
- The other apps already gate their parents pages on both platforms (Minik Math,
  Ping Pong, Retro Ping Pong, Splash, Spud/Volley/Squash, Maze). Multi Ping Pong
  and Triple Shot have no Parent Area.
