import Foundation

// Port of ui/TripleShotCharacterPickerDialog.kt (TripleShotGame 6c38131), spec 19 sections 4.2, 4.5, 4.6.2 and 8.
//
// The image-first single-character picker: a MaterialAlertDialogBuilder dialog (AndroidKit AMaterialAlertDialogBuilder:
// the M2 alert card, title, "Select" / "Cancel" text buttons in colorPrimary, ALL CAPS in English) whose view is built
// in code exactly like the Kotlin: hint, horizontal portrait strip, hero card (portrait, name, archetype, readiness
// band) and 9 rating rows with framework horizontal ProgressBars (AProgressBar style HORIZONTAL: a 4 dp bar in the
// 8 dp slot, progress in colorControlActivated #FFC83D over the colorControlNormal track, mirrored in RTL).
// Light surface: the owner's devices run Dark Mode, where Android's DayNight theme would give this alert a dark
// surface under hard-coded dark texts (spec 19 section 8.13); AndroidKit's dialogs always use the light theme values
// (DESIGN 4.5), so the card stays white with dark text on iOS.
//
// Kept Android behaviour: the initial selection ignores canSelect; "Select" is disabled for a non-selectable choice;
// non-selectable cards stay tappable to inspect their stats; Cancel, a tap outside and Back never call back; no
// persistence, no auto-scroll to the selected card (spec 19 sections 4.2 and 8.14).
//
// iOS: Android's Back key cancels the dialog; the dialog's Cancel button and a tap outside do the same (both exist on
// Android), so no extra on-screen control is added. The card listeners capture the map that holds the cards (a cycle
// the JVM collects and ARC does not): closures hold the dialog weakly and the dismissed dialog's click listeners are
// dropped on dismiss (it is never shown again, so nothing observable changes).

/**
 * Image-first roster picker used for both the human character and the local bot.
 *
 * Preview-only characters are still visible with their stats so the roster feels like one coherent
 * cast while their full body-only FRONT/BACK/SIDE art is being prepared. Their Select button stays
 * disabled until the visual catalog reports a complete on-court pack.
 */
enum TripleShotCharacterPickerDialog {

    enum Mode: String, KotlinEnum {
        case HUMAN
        case BOT
    }

    static func show(
        fragment: AFragment,
        mode: Mode,
        profiles: [TripleShotCharacterProfile],
        currentId: String,
        canSelect: @escaping (TripleShotCharacterProfile) -> Bool,
        onSelected: @escaping (TripleShotCharacterProfile) -> Void
    ) {
        if !fragment.isAdded || profiles.isEmpty { return }

        let context = fragment.requireContext()
        let density = context.resources.displayMetrics.density
        func dp(value: Int) -> Int { return (value.toFloat() * density).toInt() }

        let outerScroll = AScrollView()
        outerScroll.isFillViewport = true

        let root = ALinearLayout()
        root.orientation = ALinearLayout.VERTICAL
        // androidx.core `setPadding(size)`: the same padding on all four sides.
        root.setPadding(dp(value: 14), dp(value: 14), dp(value: 14), dp(value: 14))
        outerScroll.addView(
            root,
            AViewGroup.LayoutParams(
                AViewGroup.LayoutParams.MATCH_PARENT,
                AViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        let hint = ATextView()
        hint.text = fragment.getString(R.string.minik_swish_character_picker_hint)
        hint.textSize = 15
        hint.setTextColor(AColor.parseColor("#3A264C"))
        hint.setPadding(0, 0, 0, dp(value: 10))
        root.addView(hint)

        let cardScroll = AHorizontalScrollView()
        cardScroll.isHorizontalScrollBarEnabled = false
        cardScroll.overScrollMode = AView.OVER_SCROLL_NEVER
        let cardRow = ALinearLayout()
        cardRow.orientation = ALinearLayout.HORIZONTAL
        cardRow.gravity = AGravity.CENTER_VERTICAL
        cardRow.setPadding(dp(value: 2), dp(value: 2), dp(value: 2), dp(value: 8))
        cardScroll.addView(cardRow)
        root.addView(
            cardScroll,
            ALinearLayout.LayoutParams(
                AViewGroup.LayoutParams.MATCH_PARENT,
                dp(value: 168)
            )
        )

        let heroCard = ACardView()
        heroCard.radius = dp(value: 16).toFloat()
        heroCard.cardElevation = dp(value: 1).toFloat()
        heroCard.setCardBackgroundColor(AColor.parseColor("#FFFDF7"))
        heroCard.strokeColor = AColor.parseColor("#DAD5C8")
        heroCard.strokeWidth = dp(value: 1)
        let hero = ALinearLayout()
        hero.orientation = ALinearLayout.HORIZONTAL
        hero.gravity = AGravity.CENTER_VERTICAL
        hero.setPadding(dp(value: 12), dp(value: 12), dp(value: 12), dp(value: 12))
        heroCard.addView(hero)
        let heroCardParams = ALinearLayout.LayoutParams(
            AViewGroup.LayoutParams.MATCH_PARENT,
            AViewGroup.LayoutParams.WRAP_CONTENT
        )
        heroCardParams.bottomMargin = dp(value: 12)
        root.addView(heroCard, heroCardParams)

        let heroImage = AImageView()
        heroImage.scaleType = AImageView.ScaleType.CENTER_INSIDE
        heroImage.adjustViewBounds = true
        let heroImageParams = ALinearLayout.LayoutParams(dp(value: 126), dp(value: 154))
        heroImageParams.marginEnd = dp(value: 12)
        hero.addView(heroImage, heroImageParams)

        let heroTextColumn = ALinearLayout()
        heroTextColumn.orientation = ALinearLayout.VERTICAL
        heroTextColumn.gravity = AGravity.CENTER_VERTICAL
        hero.addView(
            heroTextColumn,
            ALinearLayout.LayoutParams(0, AViewGroup.LayoutParams.WRAP_CONTENT, 1)
        )

        let nameText = ATextView()
        nameText.textSize = 22
        nameText.setTypeface(nameText.typeface, ATypeface.BOLD)
        nameText.setTextColor(AColor.parseColor("#142129"))
        let archetypeText = ATextView()
        archetypeText.textSize = 16
        archetypeText.setTextColor(AColor.parseColor("#4D5C64"))
        archetypeText.setPadding(0, dp(value: 3), 0, dp(value: 7))
        let availabilityText = ATextView()
        availabilityText.textSize = 15
        availabilityText.setTypeface(availabilityText.typeface, ATypeface.BOLD)
        availabilityText.setPadding(dp(value: 8), dp(value: 4), dp(value: 8), dp(value: 4))
        heroTextColumn.addView(nameText)
        heroTextColumn.addView(archetypeText)
        heroTextColumn.addView(availabilityText)

        let shootingTitle = sectionTitle(fragment: fragment, resId: R.string.minik_swish_character_stats_shooting)
        let physicalTitle = sectionTitle(fragment: fragment, resId: R.string.minik_swish_character_stats_physical)
        let defenseTitle = sectionTitle(fragment: fragment, resId: R.string.minik_swish_character_stats_defense)
        root.addView(shootingTitle)

        let shootingRows = [
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_inside),
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_mid),
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_three)
        ]
        for row in shootingRows { root.addView(row.root) }
        root.addView(physicalTitle)
        let physicalRows = [
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_speed),
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_strength),
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_height)
        ]
        for row in physicalRows { root.addView(row.root) }
        root.addView(defenseTitle)
        let defenseRows = [
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_block),
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_steal),
            ratingRow(fragment: fragment, labelRes: R.string.minik_swish_character_handle)
        ]
        for row in defenseRows { root.addView(row.root) }

        var selected =
            profiles.first { $0.id == currentId }
                ?? profiles.first!

        // `mutableMapOf<String, MaterialCardView>()`: a LinkedHashMap in roster order.
        var cards = KLinkedMap<String, ACardView>()

        for profile in profiles {
            let selectable = canSelect(profile)
            let card = ACardView()
            card.radius = dp(value: 14).toFloat()
            card.cardElevation = 0
            card.strokeWidth = dp(value: 2)
            card.strokeColor = AColor.TRANSPARENT
            card.setCardBackgroundColor(AColor.parseColor(selectable ? "#FFFFFF" : "#F4F2ED"))
            card.setAlpha(selectable ? 1 : 0.72)
            card.isClickable = true
            card.isFocusable = true
            cards[profile.id] = card

            let cardBody = ALinearLayout()
            cardBody.orientation = ALinearLayout.VERTICAL
            cardBody.gravity = AGravity.CENTER
            cardBody.setPadding(dp(value: 7), dp(value: 7), dp(value: 7), dp(value: 7))
            card.addView(cardBody)

            let image = AImageView()
            image.scaleType = AImageView.ScaleType.CENTER_INSIDE
            if let res = TripleShotCharacterVisualCatalog.previewResId(characterId: profile.id) { image.setImageResource(res) }
            cardBody.addView(
                image,
                ALinearLayout.LayoutParams(dp(value: 92), dp(value: 112))
            )

            let label = ATextView()
            label.text = profile.displayName
            label.textSize = 13.5
            label.gravity = AGravity.CENTER
            label.setTypeface(label.typeface, ATypeface.BOLD)
            label.setTextColor(AColor.parseColor("#17242C"))
            label.maxLines = 1
            cardBody.addView(label)

            let cardParams = ALinearLayout.LayoutParams(dp(value: 112), dp(value: 150))
            cardParams.marginEnd = dp(value: 8)
            cardRow.addView(card, cardParams)

            card.setOnClickListener { _ in
                selected = profile
                refreshSelection(
                    fragment: fragment,
                    profile: profile,
                    selectable: canSelect(profile),
                    cards: cards,
                    heroImage: heroImage,
                    nameText: nameText,
                    archetypeText: archetypeText,
                    availabilityText: availabilityText,
                    shootingRows: shootingRows,
                    physicalRows: physicalRows,
                    defenseRows: defenseRows
                )
            }
        }

        let dialog =
            AMaterialAlertDialogBuilder(context)
                .setTitle(
                    res: mode == Mode.HUMAN
                        ? R.string.minik_swish_choose_player_character
                        : R.string.minik_swish_choose_bot_character
                )
                .setView(outerScroll)
                .setPositiveButton(res: R.string.minik_swish_character_select, nil)
                .setNegativeButton(res: android.R.string.cancel, nil)
                .create()

        dialog.setOnShowListener { [weak dialog] _ in
            let panel = AGradientDrawable()
            panel.setColor(argbInt(0xffff5ba6)); panel.cornerRadius = dp(value: 24).toFloat()
            dialog?.window?.setBackgroundDrawable(panel)
            if let it = dialog?.getButton(AAlertDialog.BUTTON_NEGATIVE) {
                FamilySkyUi.button(button: it, colors: AColorStateList.valueOf(argbInt(0xffe91e63)))
                it.setTextColor(AColor.WHITE)
            }
            TripleShotControls.watch(root: dialog!.window!.decorView)

            func syncButton() {
                let allowed = canSelect(selected)
                dialog?.getButton(AAlertDialog.BUTTON_POSITIVE).isEnabled = allowed
            }

            dialog?.getButton(AAlertDialog.BUTTON_POSITIVE).setOnClickListener { [weak dialog] _ in
                if canSelect(selected) {
                    onSelected(selected)
                    dialog?.dismiss()
                }
            }

            refreshSelection(
                fragment: fragment,
                profile: selected,
                selectable: canSelect(selected),
                cards: cards,
                heroImage: heroImage,
                nameText: nameText,
                archetypeText: archetypeText,
                availabilityText: availabilityText,
                shootingRows: shootingRows,
                physicalRows: physicalRows,
                defenseRows: defenseRows
            )
            syncButton()

            for (id, card) in cards {
                card.setOnClickListener { _ in
                    if let profile = profiles.first(where: { $0.id == id }) {
                        selected = profile
                        refreshSelection(
                            fragment: fragment,
                            profile: profile,
                            selectable: canSelect(profile),
                            cards: cards,
                            heroImage: heroImage,
                            nameText: nameText,
                            archetypeText: archetypeText,
                            availabilityText: availabilityText,
                            shootingRows: shootingRows,
                            physicalRows: physicalRows,
                            defenseRows: defenseRows
                        )
                        syncButton()
                    }
                }
            }
        }
        // iOS memory (see the file header): break the listener cycles of the dismissed dialog's views.
        dialog.setOnDismissListener { _ in
            releaseClickListeners(view: outerScroll)
        }

        dialog.show()
    }

    /// iOS memory only: drops the click listeners of a dismissed dialog's view tree (see the file header).
    private static func releaseClickListeners(view: AView) {
        view.setOnClickListener(nil)
        if let group = view as? AViewGroup {
            for child in group.children {
                releaseClickListeners(view: child)
            }
        }
    }

    private struct RatingRow {
        var root: ALinearLayout
        var valueText: ATextView
        var progress: AProgressBar
    }

    private static func sectionTitle(fragment: AFragment, resId: AStringRes) -> ATextView {
        let title = ATextView()
        title.text = fragment.getString(resId)
        title.textSize = 16
        title.setTypeface(title.typeface, ATypeface.BOLD)
        title.setTextColor(AColor.parseColor("#24343D"))
        let d = title.resources.displayMetrics.density
        title.setPadding(0, (8 * d).toInt(), 0, (3 * d).toInt())
        return title
    }

    private static func ratingRow(fragment: AFragment, labelRes: AStringRes) -> RatingRow {
        let context = fragment.requireContext()
        let density = context.resources.displayMetrics.density
        func dp(value: Int) -> Int { return (value.toFloat() * density).toInt() }

        let root = ALinearLayout()
        root.orientation = ALinearLayout.HORIZONTAL
        root.gravity = AGravity.CENTER_VERTICAL
        root.setPadding(0, dp(value: 2), 0, dp(value: 2))
        let label = ATextView()
        label.text = fragment.getString(labelRes)
        label.textSize = 15
        label.setTextColor(AColor.parseColor("#30213F"))
        root.addView(label, ALinearLayout.LayoutParams(dp(value: 88), dp(value: 26)))

        let progress = AProgressBar(nil, android.R.attr.progressBarStyleHorizontal)
        progress.max = 100
        let progressParams = ALinearLayout.LayoutParams(0, dp(value: 8), 1)
        progressParams.marginEnd = dp(value: 8)
        root.addView(progress, progressParams)

        let value = ATextView()
        value.textSize = 15
        value.gravity = AGravity.END
        value.setTypeface(value.typeface, ATypeface.BOLD)
        value.setTextColor(AColor.parseColor("#17242C"))
        root.addView(value, ALinearLayout.LayoutParams(dp(value: 34), dp(value: 26)))

        return RatingRow(root: root, valueText: value, progress: progress)
    }

    private static func refreshSelection(
        fragment: AFragment,
        profile: TripleShotCharacterProfile,
        selectable: Bool,
        cards: KLinkedMap<String, ACardView>,
        heroImage: AImageView,
        nameText: ATextView,
        archetypeText: ATextView,
        availabilityText: ATextView,
        shootingRows: [RatingRow],
        physicalRows: [RatingRow],
        defenseRows: [RatingRow]
    ) {
        for (id, card) in cards {
            let selected = id == profile.id
            card.strokeColor =
                AColor.parseColor(selected ? "#0C8F7A" : "#D7D4CC")
            card.strokeWidth =
                ((selected ? 3 : 1).toFloat() * card.resources.displayMetrics.density).toInt()
        }

        if let res = TripleShotCharacterVisualCatalog.previewResId(characterId: profile.id) { heroImage.setImageResource(res) }
        nameText.text = profile.displayName
        archetypeText.text = archetypeLabel(fragment: fragment, archetype: profile.archetype)
        availabilityText.text =
            fragment.getString(
                selectable
                    ? R.string.minik_swish_character_ready
                    : R.string.minik_swish_character_art_pending
            )
        availabilityText.setTextColor(
            AColor.parseColor(selectable ? "#0B7B68" : "#9B5C12")
        )
        availabilityText.setBackgroundColor(
            AColor.parseColor(selectable ? "#E4F5F0" : "#FFF0D9")
        )

        let r = profile.ratings
        setRatings(rows: shootingRows, values: [r.inside, r.midRange, r.threePoint])
        setRatings(rows: physicalRows, values: [r.speed, r.strength, r.height])
        setRatings(rows: defenseRows, values: [r.blocking, r.stealing, r.ballHandling])
    }

    private static func setRatings(rows: [RatingRow], values: [Int]) {
        for (row, value) in zip(rows, values) {
            row.progress.progress = value
            row.valueText.text = String(value)
        }
    }

    private static func archetypeLabel(fragment: AFragment, archetype: BotArchetype) -> String {
        let res: AStringRes
        switch archetype {
        case .ADAPTIVE_TRAINER: res = R.string.minik_swish_archetype_adaptive
        case .BALANCED: res = R.string.minik_swish_archetype_balanced
        case .SHARPSHOOTER: res = R.string.minik_swish_archetype_sharpshooter
        case .SLASHER: res = R.string.minik_swish_archetype_slasher
        case .DEFENDER: res = R.string.minik_swish_archetype_defender
        case .BIG: res = R.string.minik_swish_archetype_big
        }
        return fragment.getString(res)
    }
}
