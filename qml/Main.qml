import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    width: 520 // this should be bigger
    height: 820 // this should be bigger too

    // ── Palette from assets/README.md ─────────────────────────────────────
    readonly property color cBg:       "#1a1420"
    readonly property color cBgHi:     "#2c2438"
    readonly property color cBgLo:     "#0a0714"
    readonly property color cText:     "#fff3d6"
    readonly property color cTextDim:  "#a89878"
    readonly property color cGold:     "#f2c040"
    readonly property color cGoldHi:   "#fff2a0"
    readonly property color cGoldLo:   "#8a6818"
    readonly property color cStone:    "#8a909c"
    readonly property color cStoneHi:  "#c8ccd4"
    readonly property color cStoneLo:  "#4d535e"
    readonly property color cCrack:    "#f4c030"
    readonly property color cRed:      "#d02828"
    readonly property color cOutline:  "#0d0b10"

    // ── Tuning (mirrors game-description §12) ─────────────────────────────
    readonly property int bricksPerLevel: 100
    readonly property int pointsBase: 10
    readonly property int hpCap: 12
    readonly property int variantStoneAt: 6
    readonly property int variantObsidianAt: 11
    readonly property real treasureChance: 0.18     // client-side roll
    readonly property real rareWeight: 0.06
    readonly property real gemWeight: 0.30
    readonly property int handSlamFps: 18
    readonly property int handLiftFps: 24
    readonly property int rockCrackedHoldMs: 100
    readonly property int kittenPopMs: 200
    readonly property int kittenDespawnMs: 1800
    readonly property real kittenWalkSpeedPxS: 80
    readonly property int treasureRiseMs: 1200
    readonly property real treasureRiseDistancePx: 80
    readonly property real treasureSwayAmplitudePx: 4
    readonly property int treasureFadeOutMs: 300

    // ── Game state ────────────────────────────────────────────────────────
    property int level: 1
    property int bricksBroken: 0
    property int score: 0
    property string playerName: "PLAYER"

    // Brick (the one currently in hand)
    property int brickHp: 2
    property int brickMaxHp: 2
    property string brickVariant: "clay"
    property real brickOpacity: 1.0
    property real brickScale: 1.0

    // Rock
    property int rockTumbleIdx: 0       // 0..3 — used only for a subtle bob
    property bool rockCracked: false

    // Hand
    property string handFrame: "windup"
    property string gameState: "idle"   // idle | slamming | breaking | new_brick
    property string lastKittenBreed: ""

    // ── Helper lookups — frame rects pulled from each atlas JSON ──────────
    function handFrameRect(name) {
        switch (name) {
            case "windup": return Qt.rect(0, 0, 48, 48)
            case "mid":    return Qt.rect(48, 0, 48, 48)
            case "impact": return Qt.rect(96, 0, 48, 48)
            case "recoil": return Qt.rect(144, 0, 48, 48)
        }
        return Qt.rect(0, 0, 48, 48)
    }

    function brickFrameRect(variant, dmg) {
        var row = variant === "stone" ? 1 : variant === "obsidian" ? 2 : 0
        return Qt.rect(dmg * 32, row * 32, 32, 32)
    }

    function kittenFrameRect(breed, pose) {
        var row = { cream: 0, gray: 1, orange: 2, black: 3 }[breed] || 0
        var col = { peek: 0, sit: 1, wave: 2 }[pose] || 0
        return Qt.rect(col * 32, row * 32, 32, 32)
    }

    function treasureFrameRect(tier, idx) {
        var row = { gold: 0, gem: 1, rare: 2 }[tier] || 0
        return Qt.rect(idx * 24, row * 24, 24, 24)
    }

    function particleFrameRect(name) {
        var idx = [ "shard_big", "shard_med", "shard_small", "shard_tiny",
                    "dust_large", "dust_small", "spark_gold", "spark_cyan" ].indexOf(name)
        if (idx < 0) idx = 0
        return Qt.rect(idx * 16, 0, 16, 16)
    }

    function iconFrameRect(name) {
        var m = {
            icon_gear:       Qt.rect(0,  48, 16, 16),
            icon_trophy:     Qt.rect(80, 48, 16, 16),
            icon_refresh:    Qt.rect(96, 48, 16, 16),
            icon_user:       Qt.rect(112,48, 16, 16),
            icon_close:      Qt.rect(128,48, 16, 16),
            icon_heart:      Qt.rect(144,48, 16, 16),
            icon_coins:      Qt.rect(32, 64, 16, 16),
            icon_level_up:   Qt.rect(48, 64, 16, 16)
        }
        return m[name] || Qt.rect(0, 0, 16, 16)
    }

    // Compute damage column 0..5 from hp ratio
    function damageColumn(hp, maxHp) {
        return Math.min(5, Math.floor((1 - hp / maxHp) * 6))
    }

    function variantForLevel(lvl) {
        if (lvl >= variantObsidianAt) return "obsidian"
        if (lvl >= variantStoneAt)    return "stone"
        return "clay"
    }

    function hpForLevel(lvl) {
        return Math.min(1 + lvl, hpCap)
    }

    function multiplier(lvl) {
        return 1 + 0.25 * (lvl - 1)
    }

    function pick(arr) { return arr[Math.floor(Math.random() * arr.length)] }

    // ── Logical design box, scaled to fit root ────────────────────────────
    // The game is designed at 360×640 logical pixels (portrait). We letterbox
    // it inside whatever size the Basecamp tab gives us.
    readonly property real designW: 360
    readonly property real designH: 640

    Item {
        id: stage
        anchors.centerIn: parent
        width: root.designW
        height: root.designH

        readonly property real fit: Math.min(root.width / root.designW, root.height / root.designH)
        transform: Scale {
            xScale: stage.fit
            yScale: stage.fit
            origin.x: root.designW / 2
            origin.y: root.designH / 2
        }

        // ── Background ────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.cBg }
                GradientStop { position: 1.0; color: root.cBgLo }
            }
        }

        // A faint grid so the retro feel reads
        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.025)
                ctx.lineWidth = 1
                for (var x = 0; x < width; x += 16) {
                    ctx.beginPath(); ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, height); ctx.stroke()
                }
                for (var y = 0; y < height; y += 16) {
                    ctx.beginPath(); ctx.moveTo(0, y + 0.5); ctx.lineTo(width, y + 0.5); ctx.stroke()
                }
            }
        }

        // ── HUD strip ─────────────────────────────────────────────────────
        Item {
            id: hud
            x: 8
            y: 8
            width: parent.width - 16
            height: 56

            Rectangle {
                anchors.fill: parent
                color: root.cBgHi
                border.color: root.cGold
                border.width: 2
                radius: 0
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 12

                // LEVEL
                RowLayout {
                    spacing: 4
                    Sprite {
                        atlasSrc: "assets/hud_chrome.png"
                        frame: root.iconFrameRect("icon_level_up")
                        pixelScale: 1.25
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "LEVEL"
                            color: root.cTextDim
                            font.pixelSize: 9
                            font.family: "Courier"
                            font.bold: true
                        }
                        Text {
                            text: root.level
                            color: root.cGoldHi
                            font.pixelSize: 18
                            font.family: "Courier"
                            font.bold: true
                        }
                    }
                }

                // Progress bricks/level
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "BRICKS " + root.bricksBroken + "/" + root.bricksPerLevel
                        color: root.cText
                        font.pixelSize: 10
                        font.family: "Courier"
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 8
                        color: root.cBgLo
                        border.color: root.cGoldLo
                        border.width: 1
                        Rectangle {
                            x: 1
                            y: 1
                            height: parent.height - 2
                            width: Math.max(0, (parent.width - 2) *
                                     (root.bricksBroken / root.bricksPerLevel))
                            color: root.cGold
                        }
                    }
                    Text {
                        text: "PLAYER: " + root.playerName
                        color: root.cTextDim
                        font.pixelSize: 8
                        font.family: "Courier"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                // SCORE
                RowLayout {
                    spacing: 4
                    Sprite {
                        atlasSrc: "assets/hud_chrome.png"
                        frame: root.iconFrameRect("icon_coins")
                        pixelScale: 1.25
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "SCORE"
                            color: root.cTextDim
                            font.pixelSize: 9
                            font.family: "Courier"
                            font.bold: true
                        }
                        Text {
                            text: root.score
                            color: root.cGoldHi
                            font.pixelSize: 18
                            font.family: "Courier"
                            font.bold: true
                        }
                    }
                }
            }
        }

        // ── Play field ────────────────────────────────────────────────────

        // Rock mantle — synthesized because no rock atlas is supplied.
        // Mimics a pixel-art stone slab floating mid-air with a subtle bob.
        Item {
            id: rock
            width: 96
            height: 24
            x: (parent.width - width) / 2
            y: 470 + (root.rockTumbleIdx % 2 === 0 ? 0 : 1)    // 1px bob with the tumble clock

            Rectangle {
                anchors.fill: parent
                color: root.cStoneLo
                border.color: root.cOutline
                border.width: 2
            }
            Rectangle {
                x: 2; y: 2
                width: parent.width - 4
                height: 6
                color: root.cStoneHi
            }
            Rectangle {
                x: 2; y: 8
                width: parent.width - 4
                height: 6
                color: root.cStone
            }
            // Cracked flash — only visible during the 100 ms hold.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.75
                height: 3
                color: root.cCrack
                rotation: -8
                opacity: root.rockCracked ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 60 } }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 3
                height: parent.height * 0.6
                color: root.cCrack
                rotation: 20
                opacity: root.rockCracked ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 60 } }
            }
        }

        // Brick
        Sprite {
            id: brickSprite
            atlasSrc: "assets/brick_states.png"
            frame: root.brickFrameRect(root.brickVariant,
                                       root.damageColumn(root.brickHp, root.brickMaxHp))
            pixelScale: 2.0
            visible: root.brickHp > 0 && root.gameState !== "breaking"
            opacity: root.brickOpacity
            scale: root.brickScale
            transformOrigin: Item.Center
            x: (stage.width - width) / 2
            y: 410
        }

        // Hand
        Sprite {
            id: handSprite
            atlasSrc: "assets/hand.png"
            frame: root.handFrameRect(root.handFrame)
            pixelScale: 2.0
            x: (stage.width - width) / 2
            y: 330
        }

        // Particles, kittens, treasures — all additive overlays.
        Repeater {
            model: particleModel
            delegate: Item {
                x: model.px
                y: model.py
                opacity: Math.max(0, model.life / model.maxLife)
                Sprite {
                    atlasSrc: "assets/particles.png"
                    frame: root.particleFrameRect(model.frameName)
                    pixelScale: 1.5
                }
            }
        }

        Repeater {
            model: kittenModel
            delegate: Item {
                x: model.kx
                y: model.ky
                opacity: model.alpha
                scale: model.kscale
                transformOrigin: Item.BottomLeft
                Sprite {
                    atlasSrc: "assets/kittens.png"
                    frame: root.kittenFrameRect(model.breed, model.pose)
                    pixelScale: 1.75
                }
            }
        }

        Repeater {
            model: treasureModel
            delegate: Item {
                x: model.tx + model.sway
                y: model.ty
                opacity: model.alpha
                Sprite {
                    atlasSrc: "assets/treasure.png"
                    frame: root.treasureFrameRect(model.tier, model.frameIdx)
                    pixelScale: 1.75
                }
            }
        }

        // Hint text (fades out after first slam)
        Text {
            id: hint
            text: "TAP THE BRICK"
            color: root.cGoldHi
            font.pixelSize: 14
            font.family: "Courier"
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
            y: 540
            opacity: root.gameState === "idle" && root.bricksBroken === 0 &&
                     root.brickHp === root.brickMaxHp ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }

        // Input — hit rect restricted to the brick + 12px padding
        MouseArea {
            id: brickHit
            x: brickSprite.x - 12
            y: brickSprite.y - 12
            width: brickSprite.width + 24
            height: brickSprite.height + 24
            onClicked: root.onSlam()
        }
    }

    // ── Sprite component (atlas frame sub-rect, pixel-scaled) ─────────────
    component Sprite: Item {
        property url atlasSrc
        property rect frame: Qt.rect(0, 0, 0, 0)
        property real pixelScale: 1.0
        width:  frame.width  * pixelScale
        height: frame.height * pixelScale
        clip: true
        Image {
            source: parent.atlasSrc
            x: -parent.frame.x * parent.pixelScale
            y: -parent.frame.y * parent.pixelScale
            width:  sourceSize.width  * parent.pixelScale
            height: sourceSize.height * parent.pixelScale
            smooth: false
            mipmap: false
            fillMode: Image.Stretch
        }
    }

    // ── Data models ───────────────────────────────────────────────────────
    ListModel { id: particleModel }
    ListModel { id: kittenModel }
    ListModel { id: treasureModel }

    // ── Timers ────────────────────────────────────────────────────────────

    // 60 Hz physics / life-tick for particles, kittens, treasures.
    Timer {
        id: physicsClock
        interval: 16
        repeat: true
        running: true
        property real lastT: Date.now()
        onTriggered: {
            var now = Date.now()
            var dt = (now - lastT) / 1000.0
            if (dt > 0.1) dt = 0.1
            lastT = now
            root.stepParticles(dt)
            root.stepKittens(dt)
            root.stepTreasures(dt)
        }
    }

    // Rock tumble — 12 fps, loops forever; we only use it for a subtle bob.
    Timer {
        interval: Math.round(1000 / 12)
        repeat: true
        running: true
        onTriggered: root.rockTumbleIdx = (root.rockTumbleIdx + 1) % 4
    }

    // ── Slam choreography ─────────────────────────────────────────────────

    // Forward slam (18 fps): windup → mid → impact → recoil
    SequentialAnimation {
        id: slamAnim
        running: false

        ScriptAction { script: root.handFrame = "windup" }
        PauseAnimation { duration: Math.round(1000 / root.handSlamFps) }

        ScriptAction { script: root.handFrame = "mid" }
        PauseAnimation { duration: Math.round(1000 / root.handSlamFps) }

        ScriptAction { script: { root.handFrame = "impact"; root.onImpact() } }
        PauseAnimation { duration: Math.round(1000 / root.handSlamFps) }

        ScriptAction { script: root.handFrame = "recoil" }
        PauseAnimation { duration: Math.round(1000 / root.handSlamFps) }

        ScriptAction { script: root.afterSlam() }
    }

    // Reverse lift (24 fps): recoil → impact → mid → windup.
    // Crossfades the new brick in starting at the `mid` step.
    SequentialAnimation {
        id: liftAnim
        running: false

        ScriptAction { script: root.handFrame = "recoil" }
        PauseAnimation { duration: Math.round(1000 / root.handLiftFps) }

        ScriptAction { script: root.handFrame = "impact" }
        PauseAnimation { duration: Math.round(1000 / root.handLiftFps) }

        ScriptAction {
            script: {
                root.handFrame = "mid"
                root.spawnNextBrick()       // brickOpacity will animate up
            }
        }
        PauseAnimation { duration: Math.round(1000 / root.handLiftFps) }

        ScriptAction { script: root.handFrame = "windup" }
        PauseAnimation { duration: Math.round(1000 / root.handLiftFps) }

        ScriptAction { script: root.gameState = "idle" }
    }

    // Fades a freshly-spawned brick into visibility over 120 ms.
    NumberAnimation {
        id: brickFadeIn
        target: root
        property: "brickOpacity"
        from: 0
        to: 1
        duration: 120
    }
    NumberAnimation {
        id: brickScaleIn
        target: root
        property: "brickScale"
        from: 0.6
        to: 1.0
        duration: 120
        easing.type: Easing.OutCubic
    }

    // Flash the rock's `cracked` state for ROCK_CRACKED_HOLD_MS
    Timer {
        id: rockCrackedHold
        interval: root.rockCrackedHoldMs
        repeat: false
        onTriggered: root.rockCracked = false
    }

    // ── Input + state machine hooks ───────────────────────────────────────

    function onSlam() {
        if (gameState !== "idle") return
        if (brickHp <= 0) return
        gameState = "slamming"
        slamAnim.restart()
    }

    function onImpact() {
        brickHp -= 1
        rockCracked = true
        rockCrackedHold.restart()
        if (brickHp <= 0) {
            doBreak()
        }
    }

    function afterSlam() {
        if (gameState === "breaking") {
            // Break already started — lift in the new brick.
            handFrame = "recoil"
            liftAnim.restart()
        } else {
            handFrame = "windup"
            gameState = "idle"
        }
    }

    function doBreak() {
        gameState = "breaking"

        // Score first so the HUD tick is on the same beat.
        score += Math.round(pointsBase * multiplier(level))
        bricksBroken += 1
        if (bricksBroken >= bricksPerLevel) {
            bricksBroken = 0
            level += 1
        }

        // Particles (from the brick's former position).
        var bx = brickSprite.x + brickSprite.width / 2
        var by = brickSprite.y + brickSprite.height / 2
        emitBrickBreak(bx, by)

        // Kitten (always).
        spawnKitten(bx, by)

        // Treasure (probabilistic, client-side).
        if (Math.random() < treasureChance) {
            var r = Math.random()
            var tier = r < rareWeight
                       ? "rare"
                       : (r < rareWeight + gemWeight ? "gem" : "gold")
            spawnTreasure(bx, by, tier)
        }
    }

    function spawnNextBrick() {
        brickVariant = variantForLevel(level)
        brickMaxHp = hpForLevel(level)
        brickHp = brickMaxHp
        brickOpacity = 0
        brickScale = 0.6
        brickFadeIn.restart()
        brickScaleIn.restart()
    }

    // ── Particles ─────────────────────────────────────────────────────────

    function emitBrickBreak(x, y) {
        var names = [ "shard_big", "shard_med", "shard_small", "shard_tiny",
                      "dust_large", "dust_small" ]
        for (var i = 0; i < 12; i++) {
            var speed = 60 + Math.random() * 120    // 60..180 px/s
            var angle = -Math.PI * (0.15 + Math.random() * 0.7)   // upward cone
            var vx = Math.cos(angle) * speed
            var vy = Math.sin(angle) * speed
            particleModel.append({
                px: x - 8,
                py: y - 8,
                vx: vx,
                vy: vy,
                gravity: 240,
                life: 0.6,
                maxLife: 0.6,
                frameName: pick(names)
            })
        }
    }

    function emitTreasureSparks(x, y, tier) {
        var names = tier === "gem" ? [ "spark_cyan" ]
                  : tier === "rare" ? [ "spark_gold", "spark_cyan" ]
                  : [ "spark_gold" ]
        for (var i = 0; i < 6; i++) {
            var speed = 40 + Math.random() * 60
            var angle = Math.random() * Math.PI * 2
            particleModel.append({
                px: x - 8,
                py: y - 8,
                vx: Math.cos(angle) * speed,
                vy: Math.sin(angle) * speed,
                gravity: 40,
                life: 0.8,
                maxLife: 0.8,
                frameName: pick(names)
            })
        }
    }

    function stepParticles(dt) {
        // Walk the model in reverse so removes don't shift the cursor.
        for (var i = particleModel.count - 1; i >= 0; i--) {
            var p = particleModel.get(i)
            var life = p.life - dt
            if (life <= 0) {
                particleModel.remove(i)
                continue
            }
            particleModel.setProperty(i, "px",   p.px + p.vx * dt)
            particleModel.setProperty(i, "py",   p.py + p.vy * dt)
            particleModel.setProperty(i, "vy",   p.vy + p.gravity * dt)
            particleModel.setProperty(i, "life", life)
        }
    }

    // ── Kittens ───────────────────────────────────────────────────────────

    function pickKittenBreed() {
        var breeds = [ "cream", "gray", "orange", "black" ]
        var choice
        do { choice = pick(breeds) } while (choice === lastKittenBreed && breeds.length > 1)
        lastKittenBreed = choice
        return choice
    }

    function spawnKitten(x, y) {
        var dir = Math.random() < 0.5 ? -1 : 1
        // Cap at 12 concurrent — evict oldest.
        while (kittenModel.count >= 12) kittenModel.remove(0)
        kittenModel.append({
            kx: x - 28,                  // rough center-bottom of a 32px sprite
            ky: y - 12,
            baseY: y - 12,
            vxSign: dir,
            breed: pickKittenBreed(),
            pose: "peek",
            age: 0,
            kscale: 0.6,
            alpha: 1.0
        })
    }

    function stepKittens(dt) {
        for (var i = kittenModel.count - 1; i >= 0; i--) {
            var k = kittenModel.get(i)
            var age = k.age + dt
            var ageMs = age * 1000

            if (ageMs >= kittenDespawnMs) {
                kittenModel.remove(i)
                continue
            }

            var props = { age: age }
            if (ageMs < kittenPopMs) {
                // Pop: bounce + scale from 0.6 → 1.0.
                var t = ageMs / kittenPopMs   // 0..1
                props.pose = "peek"
                props.kscale = 0.6 + 0.4 * (1 - Math.pow(1 - t, 3))   // ease-out cubic
                var bounceY = -10 * Math.sin(t * Math.PI)
                props.ky = k.baseY + bounceY
            } else if (ageMs < kittenPopMs + 150) {
                props.pose = "wave"
                props.kscale = 1.0
                props.ky = k.baseY
            } else {
                // Walk off-screen horizontally.
                var walkT = (ageMs - kittenPopMs - 150) / 1000   // seconds walking
                props.pose = (Math.floor(ageMs / 180) % 2 === 0) ? "wave" : "sit"
                props.kx = k.kx + k.vxSign * kittenWalkSpeedPxS * dt
                props.ky = k.baseY
                // Fade out over the final 300ms
                var remaining = kittenDespawnMs - ageMs
                if (remaining < 300) props.alpha = Math.max(0, remaining / 300)
            }

            for (var key in props) kittenModel.setProperty(i, key, props[key])
        }
    }

    // ── Treasures ─────────────────────────────────────────────────────────

    function spawnTreasure(x, y, tier) {
        var bonus = tier === "rare" ? 250 : tier === "gem" ? 75 : 25
        score += Math.round(bonus * multiplier(level))
        emitTreasureSparks(x, y, tier)

        treasureModel.append({
            tier: tier,
            tx: x - 12,
            ty: y - 12,
            baseY: y - 12,
            sway: 0,
            age: 0,
            frameIdx: 0,
            alpha: 1.0
        })
    }

    function stepTreasures(dt) {
        for (var i = treasureModel.count - 1; i >= 0; i--) {
            var t = treasureModel.get(i)
            var age = t.age + dt
            var ageMs = age * 1000

            if (ageMs >= treasureRiseMs) {
                treasureModel.remove(i)
                continue
            }

            var frameFps = t.tier === "rare" ? 10 : 8
            var frameIdxLoop = Math.floor(age * frameFps) % 4
            var frameIdx = [0, 1, 2, 1][frameIdxLoop]   // sparkle pattern

            var progress = ageMs / treasureRiseMs
            // Ease-out cubic: 1 - (1 - p)^3
            var eased = 1 - Math.pow(1 - progress, 3)
            var ty = t.baseY - treasureRiseDistancePx * eased

            var sway = treasureSwayAmplitudePx *
                       Math.sin(progress * Math.PI * 2 * 1)   // 1 full cycle

            var alpha = 1.0
            var remaining = treasureRiseMs - ageMs
            if (remaining < treasureFadeOutMs) {
                alpha = Math.max(0, remaining / treasureFadeOutMs)
            }

            treasureModel.setProperty(i, "age",      age)
            treasureModel.setProperty(i, "ty",       ty)
            treasureModel.setProperty(i, "sway",     sway)
            treasureModel.setProperty(i, "frameIdx", frameIdx)
            treasureModel.setProperty(i, "alpha",    alpha)
        }
    }

    // ── Boot ──────────────────────────────────────────────────────────────
    Component.onCompleted: spawnNextBrick()
}
