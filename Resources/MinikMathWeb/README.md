# Minik Plus Web Prototype v3

Responsive static prototype for desktop, Android phones/tablets, and iPhone/iPad.

## Mobile polish
- iPhone safe-area / notch support
- Android and iOS dynamic viewport height (`dvh`)
- 44px+ touch targets
- Phone portrait and phone landscape layouts
- Touch-friendly Ping Pong controls
- No sticky hover behavior on touch devices
- Quiz equations remain LTR in every language
- Mobile-sized success/failure mascot animations
- Responsive final-score and menu layouts

## Run
Open `index.html` directly, or:

```bash
python -m http.server 8080
```

Then visit `http://localhost:8080`.

For best mobile testing, open that address from a phone on the same Wi-Fi network using your PC's local IP address.

## Language / direction behavior
- Hebrew browser/device locale (`he`, legacy `iw`, or regional variants) opens in Hebrew + RTL.
- Every other browser/device locale opens in English + LTR.
- Arithmetic expressions, multiplication tables, numeric answers, scores, and other math-only content remain LTR in both languages.
- The Minik logo stays fixed at the top: right side in RTL, left side in LTR.

## v5 interaction polish
- Dedicated Minik ping-pong art in the home menu and ping-pong screen.
- Wrong answer: no automatic question advance and no immediate correct-answer reveal.
- Wrong answer animates the in-place mascot through a short “no” sequence, then returns to the original mascot.
- A localized Next / הבא button appears only after a wrong answer.
- The learner may try another answer instead; a correct retry advances normally and removes Next.
- Success animation randomly uses a left arc, mirrored right arc, or vertical jump and stays opaque until late in the descent.
- Desktop layout is compressed to fit a normal PC viewport without vertical scrolling when sufficient height is available.

## v6 Ping Pong geometry fix
The canvas now always preserves its native 900×560 aspect ratio on desktop, Android, and iPhone. CSS no longer stretches the drawing surface vertically, so the ball stays circular and paddles keep their intended proportions.

## v7 refinements
- Added larger spacing above Next / הבא.
- Wrong-answer mascot now performs a slower subtle in-place “no” gesture and returns naturally to its original pose.
- Success mascot uses requestAnimationFrame for smooth continuous arcs/vertical motion rather than sparse CSS keyframes.
- Number selection is always ordered 1→9 left-to-right and shows plain numbers (no × prefix).
- Hebrew copy no longer leaves “Minik” in English in the number-selection text.
- Home math card now offers Multiply / Divide (כפל / חילוק) directly. If one is chosen there, number selection goes straight into that quiz and skips the later mode-choice screen.
- Generic “Start practicing” still preserves the older learn-table flow.

## v8 focused fixes
- Ping Pong is first to 3.
- Pong scores are explicitly mapped: You on the left, Minik on the right, regardless of RTL/LTR.
- Removed the dark table/court surface while keeping the dotted center line.
- Multiplication and division now use the same Minik mascot.
- Added a gold mode title to the number-selection screen when the mode is known, and to every quiz screen.
- No other flows or interactions were changed.
