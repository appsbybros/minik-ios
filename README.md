# Minik iOS apps

This repository holds **all** the Minik iOS apps. They are one Xcode project (`project.yml`) and share code and
resources: Minik Plus (with its English-only flavour), Minik Math, Minik Math Plus, Minik Ping Pong, Minik Retro
Ping Pong, Minik Multi Ping Pong, Minik Spud, Minik Splash, Minik Squash and Minik Beach Volley.

Build: on macOS run `xcodegen generate`, then build the app's scheme. Every GitHub workflow here is started by
hand or by the owner's release script; a push starts nothing.

---

# Minik iOS

iOS development is performed primarily on Windows, with compilation and device testing performed later on macOS.

The canonical project handoff is [`docs/MINIK_MASTER_PLAN.md`](docs/MINIK_MASTER_PLAN.md). Before proposing or implementing product work, read it completely, followed by [`../AGENTS.md`](../AGENTS.md), [`docs/android-known-fixes.md`](docs/android-known-fixes.md), and the [Android UI reference index](docs/reference/android-ui/README.md).

Do not overwrite the product-contract sections of the master plan when updating progress. Update its designated living status, decision log, sprint log, and progress sections unless the user explicitly changes a product requirement or a verified fact requires correction.

[`project.yml`](project.yml) is the source of truth for the Xcode project. On macOS, install XcodeGen and run `xcodegen generate` from this directory to produce the `.xcodeproj`. Never treat edits to the generated Xcode project as authoritative; update `project.yml` and regenerate it instead.

The canonical Apple bundle identifiers use the `com.appsbybros.minik` namespace and are declared in `project.yml`. No signing credentials or secrets belong in the project definition.

Git operations follow the rules and any explicitly active exceptions in [`../AGENTS.md`](../AGENTS.md).
