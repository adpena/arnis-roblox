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

    local previewAnchor = AustinSpawn.resolveAnchor(manifest, 500)
    Assert.near(
        previewAnchor.spawnPoint.X,
        25,
        0.001,
        "expected preview anchor selection to keep the nearby walkable footway midpoint"
    )
    Assert.near(previewAnchor.spawnPoint.Z, 0, 0.001, "expected preview anchor Z from selected footway")

    local runtimeSpawnPoint = AustinSpawn.findSpawnPoint(manifest, 500)
    Assert.near(
        runtimeSpawnPoint.X,
        150,
        0.001,
        "expected runtime spawn selection to prefer the nearby driveable primary road over a footway"
    )
    Assert.near(runtimeSpawnPoint.Z, 0, 0.001, "expected runtime spawn Z from selected primary road")

    local gameplaySpawnManifest = {
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
                            { x = 40, y = 0, z = 0 },
                        },
                    },
                    {
                        kind = "service",
                        points = {
                            { x = 0, y = 0, z = 16 },
                            { x = 40, y = 0, z = 16 },
                        },
                    },
                },
            },
        },
    }

    local gameplaySpawnPoint = AustinSpawn.findSpawnPoint(gameplaySpawnManifest, 500)
    Assert.near(
        gameplaySpawnPoint.X,
        20,
        0.001,
        "expected gameplay spawn to stay on the local service road midpoint X when a nearby footway also exists"
    )
    Assert.near(
        gameplaySpawnPoint.Z,
        16,
        0.001,
        "expected gameplay spawn to prefer a nearby service road over a pedestrian footway"
    )

    local gameplayPreviewAnchor = AustinSpawn.resolveAnchor(gameplaySpawnManifest, 500)
    Assert.near(
        gameplayPreviewAnchor.spawnPoint.Z,
        0,
        0.001,
        "expected preview anchor selection to preserve the previous footway-biased preview road focus"
    )

    local gameplayRuntimeAnchor = AustinSpawn.resolveRuntimeAnchor(gameplaySpawnManifest, 500)
    Assert.near(
        gameplayRuntimeAnchor.spawnPoint.Z,
        16,
        0.001,
        "expected runtime anchor selection to use the gameplay-safe service-road spawn policy"
    )

    local openStreetManifest = {
        meta = {
            chunkSizeStuds = 256,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "service",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 40, y = 0, z = 0 },
                        },
                    },
                    {
                        kind = "service",
                        points = {
                            { x = 96, y = 0, z = 0 },
                            { x = 136, y = 0, z = 0 },
                        },
                    },
                },
                buildings = {
                    {
                        baseY = 0,
                        height = 24,
                        footprint = {
                            { x = 0, z = 12 },
                            { x = 40, z = 12 },
                            { x = 40, z = 52 },
                            { x = 0, z = 52 },
                        },
                    },
                },
            },
        },
    }

    local openStreetSpawn = AustinSpawn.findSpawnPoint(openStreetManifest, 500, Vector3.new(20, 0, 0))
    Assert.near(
        openStreetSpawn.X,
        116,
        0.001,
        "expected runtime spawn to prefer the more open road segment over one that hugs a nearby building footprint"
    )
    Assert.near(openStreetSpawn.Z, 0, 0.001, "expected runtime spawn to remain on the open-road midpoint Z")

    local openStreetPreviewFocus = AustinSpawn.findPreviewFocusPoint(openStreetManifest, 500, Vector3.new(20, 0, 0))
    Assert.near(
        openStreetPreviewFocus.X,
        20,
        0.001,
        "expected preview focus to preserve the caller-provided load center even when runtime spawn avoids dense building edges"
    )

    local denseClusterManifest = {
        meta = {
            chunkSizeStuds = 256,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "service",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 40, y = 0, z = 0 },
                        },
                    },
                    {
                        kind = "service",
                        points = {
                            { x = 120, y = 0, z = 0 },
                            { x = 160, y = 0, z = 0 },
                        },
                    },
                },
                buildings = {
                    {
                        baseY = 0,
                        height = 24,
                        footprint = {
                            { x = -10, z = 88 },
                            { x = 50, z = 88 },
                            { x = 50, z = 128 },
                            { x = -10, z = 128 },
                        },
                    },
                    {
                        baseY = 0,
                        height = 24,
                        footprint = {
                            { x = -10, z = -128 },
                            { x = 50, z = -128 },
                            { x = 50, z = -88 },
                            { x = -10, z = -88 },
                        },
                    },
                    {
                        baseY = 0,
                        height = 24,
                        footprint = {
                            { x = -116, z = -40 },
                            { x = -76, z = -40 },
                            { x = -76, z = 40 },
                            { x = -116, z = 40 },
                        },
                    },
                },
            },
        },
    }

    local denseClusterSpawn = AustinSpawn.findSpawnPoint(denseClusterManifest, 500, Vector3.new(20, 0, 0))
    Assert.near(
        denseClusterSpawn.X,
        140,
        0.001,
        "expected runtime spawn to avoid a service-road midpoint boxed in by several nearby buildings even when none crosses the direct clearance threshold"
    )
    Assert.near(denseClusterSpawn.Z, 0, 0.001, "expected dense-cluster avoidance to keep the open-road midpoint Z")

    local roofOnlyHazardManifest = {
        meta = {
            chunkSizeStuds = 256,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "service",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 40, y = 0, z = 0 },
                        },
                    },
                    {
                        kind = "service",
                        points = {
                            { x = 120, y = 0, z = 0 },
                            { x = 160, y = 0, z = 0 },
                        },
                    },
                },
                buildings = {
                    {
                        usage = "roof",
                        baseY = 24,
                        minHeight = 24,
                        height = 12,
                        footprint = {
                            { x = -10, z = 130 },
                            { x = 50, z = 130 },
                            { x = 50, z = 170 },
                            { x = -10, z = 170 },
                        },
                    },
                },
            },
        },
    }

    local roofOnlyHazardSpawn = AustinSpawn.findSpawnPoint(roofOnlyHazardManifest, 500, Vector3.new(20, 0, 0))
    Assert.near(
        roofOnlyHazardSpawn.X,
        140,
        0.001,
        "expected runtime spawn to treat a nearby roof-only structure as a stronger hazard than a similarly distant open service road"
    )
    Assert.near(roofOnlyHazardSpawn.Z, 0, 0.001, "expected roof-only hazard avoidance to preserve the open-road midpoint Z")

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
    Assert.near(focusPoint.Y, 0, 0.001, "expected focus Y to stay grounded instead of averaging building tops")

    local groundedSpawn = AustinSpawn.findSpawnPoint(tallBuildingManifest, 500)
    Assert.near(groundedSpawn.X, 20, 0.001, "expected grounded road midpoint to remain the spawn target")
    Assert.near(groundedSpawn.Y, 0, 0.001, "expected spawn Y to stay on the road, not in the air")

    local remoteAustinManifest = {
        meta = {
            chunkSizeStuds = 256,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "motorway",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 64, y = 0, z = 0 },
                        },
                    },
                },
            },
            {
                id = "16_16",
                originStuds = { x = 4096, y = 0, z = 4096 },
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

    local remoteAnchor = AustinSpawn.resolveAnchor(remoteAustinManifest, 500)
    Assert.near(
        remoteAnchor.spawnPoint.X,
        4116,
        0.001,
        "expected anchor resolution without an explicit load center to search the full manifest instead of clipping to world origin"
    )
    Assert.near(
        remoteAnchor.spawnPoint.Z,
        4096,
        0.001,
        "expected anchor resolution without an explicit load center to preserve the remote populated chunk Z"
    )

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
    Assert.near(canonicalSpawn.X, 20, 0.001, "expected canonical Austin anchor to preserve road midpoint X")
    Assert.near(
        canonicalSpawn.Z,
        0,
        0.001,
        "expected canonical anchor metadata to bias road selection without moving the final spawn off-road"
    )

    local lookTarget = AustinSpawn.getPreferredLookTarget(canonicalAustinManifest, canonicalSpawn, Vector3.new(0, 0, 0))
    Assert.truthy(lookTarget.Z > canonicalSpawn.Z, "expected canonical Austin facing direction to point south")

    local canonicalPreviewFocus = AustinSpawn.findPreviewFocusPoint(canonicalAustinManifest, 500)
    Assert.near(
        canonicalPreviewFocus.X,
        20,
        0.001,
        "expected preview focus X to preserve the heuristic load center when using a relative spawn offset"
    )
    Assert.near(
        canonicalPreviewFocus.Z,
        0,
        0.001,
        "expected preview focus Z to preserve the heuristic load center when using a relative spawn offset"
    )

    local canonicalAnchor = AustinSpawn.resolveAnchor(canonicalAustinManifest, 500)
    Assert.near(
        canonicalAnchor.focusPoint.X,
        20,
        0.001,
        "expected resolved anchor focus X to preserve the heuristic load center for relative offsets"
    )
    Assert.near(
        canonicalAnchor.focusPoint.Z,
        0,
        0.001,
        "expected resolved anchor focus Z to preserve the heuristic load center for relative offsets"
    )
    Assert.near(
        canonicalAnchor.spawnPoint.Z,
        canonicalSpawn.Z,
        0.001,
        "expected resolved anchor spawn Z to stay on the selected road while preserving canonical bias"
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
        20,
        0.001,
        "expected sharded handle preview focus X to preserve the heuristic load center for relative offsets"
    )
    Assert.near(
        handlePreviewFocus.Z,
        0,
        0.001,
        "expected sharded handle preview focus Z to preserve the heuristic load center for relative offsets"
    )

    local handleAnchor = AustinSpawn.resolveAnchor(shardedHandleLikeManifest, 500)
    Assert.near(
        handleAnchor.focusPoint.X,
        20,
        0.001,
        "expected sharded handle resolved anchor focus X to preserve heuristic load center"
    )
    Assert.near(
        handleAnchor.focusPoint.Z,
        0,
        0.001,
        "expected sharded handle resolved anchor focus Z to preserve heuristic load center"
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
    Assert.near(explicitAnchor.spawnPoint.X, 123, 0.001, "expected explicit canonical anchor X to win over heuristics")
    Assert.near(explicitAnchor.spawnPoint.Y, 7, 0.001, "expected explicit canonical anchor Y to win over heuristics")
    Assert.near(explicitAnchor.spawnPoint.Z, -456, 0.001, "expected explicit canonical anchor Z to win over heuristics")
    Assert.near(explicitAnchor.focusPoint.X, 123, 0.001, "expected explicit canonical focus X to match explicit spawn")
    Assert.near(explicitAnchor.focusPoint.Z, -456, 0.001, "expected explicit canonical focus Z to match explicit spawn")
end
