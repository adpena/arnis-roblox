return function()
    local AustinSpawn = require(script.Parent.Parent.ImportService.AustinSpawn)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        meta = {
            chunkSizeStuds = 256,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "footway",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 50, y = 0, z = 0 },
                        },
                    },
                    {
                        kind = "primary",
                        points = {
                            { x = 100, y = 0, z = 0 },
                            { x = 200, y = 0, z = 0 },
                        },
                    },
                },
            },
            {
                id = "5_5",
                originStuds = { x = 1280, y = 0, z = 1280 },
                roads = {
                    {
                        kind = "primary",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 100, y = 0, z = 0 },
                        },
                    },
                },
            },
        },
    }

    local spawnPoint = AustinSpawn.findSpawnPoint(manifest, 500)
    Assert.near(
        spawnPoint.X,
        25,
        0.001,
        "expected nearby walkable road midpoint to win over primary road"
    )
    Assert.near(spawnPoint.Z, 0, 0.001, "expected spawn Z from selected road")

    local tallBuildingManifest = {
        meta = {
            chunkSizeStuds = 256,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "residential",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 40, y = 0, z = 0 },
                        },
                    },
                },
                buildings = {
                    {
                        baseY = 0,
                        height = 160,
                        footprint = {
                            { x = 80, z = -20 },
                            { x = 140, z = -20 },
                            { x = 140, z = 20 },
                            { x = 80, z = 20 },
                        },
                    },
                },
            },
        },
    }

    local focusPoint = AustinSpawn.findFocusPoint(tallBuildingManifest)
    Assert.near(
        focusPoint.Y,
        0,
        0.001,
        "expected focus Y to stay grounded instead of averaging building tops"
    )

    local groundedSpawn = AustinSpawn.findSpawnPoint(tallBuildingManifest, 500)
    Assert.near(
        groundedSpawn.X,
        20,
        0.001,
        "expected grounded road midpoint to remain the spawn target"
    )
    Assert.near(groundedSpawn.Y, 0, 0.001, "expected spawn Y to stay on the road, not in the air")

    local skewedManifest = {
        meta = {
            chunkSizeStuds = 256,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "residential",
                        points = {
                            { x = 16, y = 0, z = 16 },
                            { x = 48, y = 0, z = 16 },
                        },
                    },
                },
                buildings = {
                    {
                        baseY = 0,
                        height = 24,
                        footprint = {
                            { x = 24, z = 24 },
                            { x = 56, z = 24 },
                            { x = 56, z = 56 },
                            { x = 24, z = 56 },
                        },
                    },
                },
            },
            {
                id = "10_10",
                originStuds = { x = 2560, y = 0, z = 2560 },
                roads = {},
                buildings = {},
                props = {},
            },
        },
    }

    local skewedFocus = AustinSpawn.findFocusPoint(skewedManifest)
    Assert.truthy(
        skewedFocus.X < 200,
        "expected focus to stay near populated Austin content instead of empty extent center"
    )
    Assert.truthy(
        skewedFocus.Z < 200,
        "expected focus Z to stay near populated Austin content instead of empty extent center"
    )

    local previewFocus = AustinSpawn.findPreviewFocusPoint(skewedManifest)
    Assert.near(
        previewFocus.X,
        32,
        0.001,
        "expected preview focus X to anchor preview on the canonical spawn road rather than chunk bounds"
    )
    Assert.near(
        previewFocus.Z,
        16,
        0.001,
        "expected preview focus Z to anchor preview on the canonical spawn road rather than chunk bounds"
    )

    local canonicalAustinManifest = {
        meta = {
            chunkSizeStuds = 256,
            worldName = "ExportedWorld",
            canonicalAnchor = {
                positionOffsetFromHeuristicStuds = { x = 0, y = 0, z = -192 },
                lookDirectionStuds = { x = 0, y = 0, z = 1 },
            },
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "residential",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 40, y = 0, z = 0 },
                        },
                    },
                },
            },
        },
    }

    local canonicalSpawn = AustinSpawn.findSpawnPoint(canonicalAustinManifest, 500)
    Assert.near(
        canonicalSpawn.X,
        20,
        0.001,
        "expected canonical Austin anchor to preserve road midpoint X"
    )
    Assert.near(
        canonicalSpawn.Z,
        -192,
        0.001,
        "expected canonical anchor metadata to move spawn to the south side of the current Capitol heuristic"
    )

    local lookTarget = AustinSpawn.getPreferredLookTarget(
        canonicalAustinManifest,
        canonicalSpawn,
        Vector3.new(0, 0, 0)
    )
    Assert.truthy(
        lookTarget.Z > canonicalSpawn.Z,
        "expected canonical Austin facing direction to point south"
    )

    local canonicalPreviewFocus = AustinSpawn.findPreviewFocusPoint(canonicalAustinManifest, 500)
    Assert.near(
        canonicalPreviewFocus.X,
        canonicalSpawn.X,
        0.001,
        "expected preview focus to preserve the canonical Austin spawn X"
    )
    Assert.near(
        canonicalPreviewFocus.Z,
        canonicalSpawn.Z,
        0.001,
        "expected preview focus to match the canonical Austin spawn Z exactly"
    )

    local canonicalAnchor = AustinSpawn.resolveAnchor(canonicalAustinManifest, 500)
    Assert.near(
        canonicalAnchor.focusPoint.X,
        canonicalSpawn.X,
        0.001,
        "expected resolved anchor focus X to match the canonical spawn X"
    )
    Assert.near(
        canonicalAnchor.focusPoint.Z,
        canonicalSpawn.Z,
        0.001,
        "expected resolved anchor focus Z to match the canonical spawn Z"
    )
    Assert.near(
        canonicalAnchor.spawnPoint.Z,
        canonicalSpawn.Z,
        0.001,
        "expected resolved anchor spawn Z to preserve canonical metadata positioning"
    )
    Assert.truthy(
        canonicalAnchor.lookTarget.Z > canonicalAnchor.spawnPoint.Z,
        "expected resolved anchor look target to preserve the canonical south-facing direction"
    )

    local shardedHandleLikeManifest = {
        meta = canonicalAustinManifest.meta,
        chunkRefs = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
            },
        },
        LoadChunksWithinRadius = function(_self, center, _radius)
            Assert.truthy(center ~= nil, "expected sharded handle selection to receive a center")
            return canonicalAustinManifest.chunks
        end,
    }

    local handleSpawn = AustinSpawn.findSpawnPoint(shardedHandleLikeManifest, 500)
    Assert.near(
        handleSpawn.X,
        canonicalSpawn.X,
        0.001,
        "expected sharded handle spawn X to match materialized manifest"
    )
    Assert.near(
        handleSpawn.Z,
        canonicalSpawn.Z,
        0.001,
        "expected sharded handle spawn Z to match materialized manifest"
    )

    local handlePreviewFocus = AustinSpawn.findPreviewFocusPoint(shardedHandleLikeManifest, 500)
    Assert.near(
        handlePreviewFocus.X,
        handleSpawn.X,
        0.001,
        "expected sharded handle preview focus X to match the exact runtime spawn anchor"
    )
    Assert.near(
        handlePreviewFocus.Z,
        handleSpawn.Z,
        0.001,
        "expected sharded handle preview focus Z to match the exact runtime spawn anchor"
    )

    local handleAnchor = AustinSpawn.resolveAnchor(shardedHandleLikeManifest, 500)
    Assert.near(
        handleAnchor.focusPoint.X,
        handleSpawn.X,
        0.001,
        "expected sharded handle resolved anchor focus X to match runtime spawn"
    )
    Assert.near(
        handleAnchor.focusPoint.Z,
        handleSpawn.Z,
        0.001,
        "expected sharded handle resolved anchor focus Z to match runtime spawn"
    )
    Assert.equal(
        handleAnchor.selectedChunks,
        canonicalAustinManifest.chunks,
        "expected resolved anchor to retain the materialized chunk set for runtime reuse"
    )

    local explicitAnchorManifest = {
        meta = {
            chunkSizeStuds = 256,
            canonicalAnchor = {
                positionStuds = { x = 123, y = 7, z = -456 },
                lookDirectionStuds = { x = 0, y = 0, z = 1 },
            },
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "residential",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 40, y = 0, z = 0 },
                        },
                    },
                },
            },
        },
    }

    local explicitAnchor = AustinSpawn.resolveAnchor(explicitAnchorManifest, 500)
    Assert.near(
        explicitAnchor.spawnPoint.X,
        123,
        0.001,
        "expected explicit canonical anchor X to win over heuristics"
    )
    Assert.near(
        explicitAnchor.spawnPoint.Y,
        7,
        0.001,
        "expected explicit canonical anchor Y to win over heuristics"
    )
    Assert.near(
        explicitAnchor.spawnPoint.Z,
        -456,
        0.001,
        "expected explicit canonical anchor Z to win over heuristics"
    )
    Assert.near(
        explicitAnchor.focusPoint.X,
        123,
        0.001,
        "expected explicit canonical focus X to match explicit spawn"
    )
    Assert.near(
        explicitAnchor.focusPoint.Z,
        -456,
        0.001,
        "expected explicit canonical focus Z to match explicit spawn"
    )
end
