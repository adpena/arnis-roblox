return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
    local ImportService = require(script.Parent.Parent.ImportService)
    local MemoryGuardrail = require(script.Parent.Parent.ImportService.MemoryGuardrail)
    local StreamingService = require(script.Parent.Parent.ImportService.StreamingService)

    local originalImportChunk = ImportService.ImportChunk
    local originalImportChunkSubplan = ImportService.ImportChunkSubplan
    local originalMemoryGuardrailNew = MemoryGuardrail.New
    local importOrder = {}
    local subplanImportCount = 0
    local subplanImportOrder = {}
    local capturedInFlightTelemetryDuringImport = {}
    local memoryGuardrailAttrs = {
        "ArnisStreamingMemoryGuardrailEnabled",
        "ArnisStreamingMemoryGuardrailState",
        "ArnisStreamingMemoryGuardrailBudgetBytes",
        "ArnisStreamingMemoryGuardrailResidentEstimatedCost",
        "ArnisStreamingMemoryGuardrailInFlightEstimatedCost",
        "ArnisStreamingMemoryGuardrailProjectedUsageBytes",
        "ArnisStreamingMemoryGuardrailResumeThresholdBytes",
        "ArnisStreamingMemoryGuardrailHostProbeEnabled",
        "ArnisStreamingMemoryGuardrailHostAvailableBytes",
        "ArnisStreamingMemoryGuardrailHostPressureLevel",
        "ArnisStreamingMemoryGuardrailHostCritical",
        "ArnisStreamingMemoryGuardrailDeferredAdmissions",
        "ArnisStreamingMemoryGuardrailLastPauseReason",
    }
    local hostProbeInputAttrs = {
        "ArnisStreamingHostProbeAvailableBytes",
        "ArnisStreamingHostProbePressureLevel",
    }

    local function makeChunk(chunkId, originX)
        return {
            id = chunkId,
            originStuds = { x = originX, y = 0, z = 0 },
            roads = {},
            rails = {},
            buildings = {},
            water = {},
            props = {},
            landuse = {},
            barriers = {},
        }
    end

    local function isStreamingPriorityWorld(importOptions)
        local worldRootName = type(importOptions) == "table" and importOptions.worldRootName or nil
        return type(worldRootName) == "string"
            and string.sub(worldRootName, 1, #"StreamingPriority") == "StreamingPriority"
    end

    local function clearMemoryGuardrailAttrs()
        for _, attrName in ipairs(memoryGuardrailAttrs) do
            Workspace:SetAttribute(attrName, nil)
        end
    end

    local function clearHostProbeInputAttrs()
        for _, attrName in ipairs(hostProbeInputAttrs) do
            Workspace:SetAttribute(attrName, nil)
        end
    end

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "StreamingPriorityTest",
            generator = "test",
            source = "test",
            metersPerStud = 0.3,
            chunkSizeStuds = 100,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
        },
        chunkRefs = {
            {
                id = "near_heavy",
                originStuds = { x = -40, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 40,
                streamingCost = 800,
            },
            {
                id = "near_light",
                originStuds = { x = 20, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 2,
                streamingCost = 10,
            },
            {
                id = "far_light",
                originStuds = { x = 120, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 1,
                streamingCost = 1,
            },
            {
                id = "near_behind",
                originStuds = { x = -120, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 1,
                streamingCost = 1,
            },
        },
        GetChunk = function(_, chunkId)
            if chunkId == "near_heavy" then
                return makeChunk(chunkId, -40)
            elseif chunkId == "near_light" then
                return makeChunk(chunkId, 20)
            elseif chunkId == "near_behind" then
                return makeChunk(chunkId, -120)
            end
            return makeChunk(chunkId, 120)
        end,
    }

    local options = {
        worldRootName = "StreamingPriorityWorld",
        config = {
            StreamingEnabled = true,
            StreamingTargetRadius = 400,
            HighDetailRadius = 400,
            ChunkSizeStuds = 100,
            TerrainMode = "none",
            RoadMode = "mesh",
            BuildingMode = "shellMesh",
            WaterMode = "mesh",
            LanduseMode = "fill",
        },
        preferredLookVector = Vector3.new(1, 0, 0),
    }

    ImportService.ImportChunk = function(chunk, importOptions)
        if isStreamingPriorityWorld(importOptions) then
            capturedInFlightTelemetryDuringImport[chunk.id] =
                Workspace:GetAttribute("ArnisStreamingMemoryGuardrailInFlightEstimatedCost")
            importOrder[#importOrder + 1] = chunk.id
        end
        return originalImportChunk(chunk, importOptions)
    end
    ImportService.ImportChunkSubplan = function(chunk, subplan, importOptions)
        if isStreamingPriorityWorld(importOptions) then
            subplanImportCount += 1
            subplanImportOrder[#subplanImportOrder + 1] = if type(subplan) == "table"
                then subplan.id or subplan.layer
                else nil
        end
        return originalImportChunkSubplan(chunk, subplan, importOptions)
    end

    local ok, err = xpcall(function()
        ChunkLoader.Clear()
        StreamingService.Start(manifest, options)
        StreamingService.Update(Vector3.new(0, 0, 0))

        Assert.equal(#importOrder, 4, "expected all candidate chunks to load")
        Assert.equal(importOrder[1], "near_heavy", "expected nearest chunk in same distance band to load first")
        Assert.equal(importOrder[2], "near_light", "expected slightly farther chunk in same distance band to defer")
        Assert.equal(importOrder[3], "near_behind", "expected behind-player chunk in same band after forward chunks")
        Assert.equal(importOrder[4], "far_light", "expected farther chunk band to load after nearer band")
        Assert.equal(subplanImportCount, 0, "expected rollout-off streaming to preserve whole-chunk fallback")

        local subplanKey = ChunkPriority.BuildPriorityKey(
            {
                chunkId = "near_heavy",
                originStuds = { x = 0, y = 0, z = 0 },
                subplan = {
                    id = "roads_dense",
                    layer = "roads",
                    bounds = { minX = 0, minY = 0, maxX = 20, maxY = 20 },
                    streamingCost = 20,
                    featureCount = 4,
                },
                roads = {},
                rails = {},
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
            Vector3.new(0, 0, 0),
            100,
            nil,
            {
                ["near_heavy"] = 5,
                ["near_heavy::roads_dense"] = 17,
            },
            0
        )
        Assert.equal(
            subplanKey.observedCost,
            17,
            "expected subplan-specific observed cost to override chunk-level cost"
        )

        importOrder = {}
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local guardrailManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "guardrail_anchor",
                    originStuds = { x = -40, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 4,
                    estimatedMemoryCost = 90,
                },
                {
                    id = "guardrail_deferred",
                    originStuds = { x = 20, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 20,
                },
                {
                    id = "guardrail_resumed",
                    originStuds = { x = 1000, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 20,
                },
            },
            GetChunk = function(_, chunkId)
                if chunkId == "guardrail_anchor" then
                    return makeChunk(chunkId, -40)
                elseif chunkId == "guardrail_deferred" then
                    return makeChunk(chunkId, 20)
                end
                return makeChunk(chunkId, 1000)
            end,
        }
        local guardrailOptions = {
            worldRootName = "StreamingPriorityGuardrailWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 100,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(guardrailManifest, guardrailOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))

        Assert.equal(
            #importOrder,
            1,
            "expected admission to stop before importing a work item that would exceed the estimated memory budget"
        )
        Assert.equal(
            importOrder[1],
            "guardrail_anchor",
            "expected the already-admitted work item to finish before the pause engages"
        )
        Assert.truthy(
            ChunkLoader.GetChunkEntry("guardrail_anchor", guardrailOptions.worldRootName),
            "expected loaded scene content to remain resident when admission pauses"
        )
        Assert.falsy(
            ChunkLoader.GetChunkEntry("guardrail_deferred", guardrailOptions.worldRootName),
            "expected deferred work to remain unloaded while the guardrail is paused"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailEnabled"),
            true,
            "expected memory guardrail telemetry to publish the enabled state"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "guarded_pause",
            "expected the guardrail to enter guarded_pause after a deferred admission"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailBudgetBytes"),
            100,
            "expected telemetry to publish the estimated memory budget"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            90,
            "expected resident estimated cost telemetry to reflect the completed admitted work"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailInFlightEstimatedCost"),
            0,
            "expected in-flight estimated cost to return to zero after admitted work finishes"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailProjectedUsageBytes"),
            110,
            "expected telemetry to publish projected usage for the deferred over-budget admission"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResumeThresholdBytes"),
            85,
            "expected telemetry to publish the hysteresis resume boundary"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailDeferredAdmissions"),
            1,
            "expected telemetry to count the deferred admission for the paused update"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailLastPauseReason"),
            "budget",
            "expected telemetry to record why admission paused"
        )

        StreamingService.Update(Vector3.new(1000, 0, 0))
        Assert.equal(
            #importOrder,
            1,
            "expected the first post-pause update to unload pressure-driving content before resuming admissions"
        )
        Assert.falsy(
            ChunkLoader.GetChunkEntry("guardrail_anchor", guardrailOptions.worldRootName),
            "expected normal streaming unloads to clear resident pressure once the focal point moves away"
        )

        StreamingService.Update(Vector3.new(1000, 0, 0))
        Assert.equal(
            #importOrder,
            2,
            "expected later update cycles to resume admission once projected usage drops below the hysteresis threshold"
        )
        Assert.equal(
            importOrder[2],
            "guardrail_resumed",
            "expected resumed admission to pick the next eligible chunk for the new focal area"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "active",
            "expected the guardrail to return to active after usage falls below the hysteresis threshold"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailLastPauseReason"),
            nil,
            "expected resuming admission to clear the last pause reason"
        )

        importOrder = {}
        clearMemoryGuardrailAttrs()
        clearHostProbeInputAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local hostProbeOptions = {
            worldRootName = "StreamingPriorityHostProbeWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                StreamingMaxWorkItemsPerUpdate = 1,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 1000,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = true,
                        CriticalAvailableBytes = 64,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        Workspace:SetAttribute("ArnisStreamingHostProbeAvailableBytes", 32)
        Workspace:SetAttribute("ArnisStreamingHostProbePressureLevel", 0.25)
        StreamingService.Start(guardrailManifest, hostProbeOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(#importOrder, 0, "expected critical host probe pressure to pause admission before importing work")
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "guarded_pause",
            "expected host probe pressure to enter guarded_pause"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailLastPauseReason"),
            "host_probe",
            "expected host probe pauses to publish a deterministic reason"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailHostProbeEnabled"),
            true,
            "expected telemetry to expose whether host probe integration is enabled"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailHostAvailableBytes"),
            32,
            "expected telemetry to expose the sampled host available bytes"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailHostPressureLevel"),
            0.25,
            "expected telemetry to expose the sampled host pressure level"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailHostCritical"),
            true,
            "expected telemetry to expose when the sampled host state is critical"
        )
        clearHostProbeInputAttrs()

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local replacementManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "guardrail_reimport",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    estimatedMemoryCost = 90,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local replacementOptions = {
            worldRootName = "StreamingPriorityReplacementWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 100,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(replacementManifest, replacementOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(#importOrder, 1, "expected the initial replacement chunk load to succeed")

        local replacementEntry = ChunkLoader.GetChunkEntry("guardrail_reimport", replacementOptions.worldRootName)
        Assert.truthy(replacementEntry, "expected replacement chunk to be loaded before the refresh test")
        replacementEntry.layerSignatures = {
            terrain = "stale",
            roads = "stale",
            landuse = "stale",
            barriers = "stale",
            buildings = "stale",
            water = "stale",
            props = "stale",
        }

        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            #importOrder,
            2,
            "expected a same-chunk refresh to reuse its resident cost slot instead of pausing over duplicated accounting"
        )
        Assert.equal(
            importOrder[2],
            "guardrail_reimport",
            "expected the refresh pass to reimport the same visible chunk"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "active",
            "expected same-slot chunk replacement not to leave the guardrail paused"
        )

        importOrder = {}
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local residentIgnoredRefreshManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "resident_ignored_refresh",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    estimatedMemoryCost = 64,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local residentIgnoredWarmOptions = {
            worldRootName = "StreamingPriorityResidentIgnoredRefreshWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 128,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = false,
                    CountInFlightCost = false,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }
        local residentIgnoredStrictOptions = {
            worldRootName = "StreamingPriorityResidentIgnoredRefreshWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "parts",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 32,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = false,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(residentIgnoredRefreshManifest, residentIgnoredWarmOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(#importOrder, 1, "expected the warm pass to load the resident refresh chunk")

        StreamingService.Stop()
        StreamingService.Start(residentIgnoredRefreshManifest, residentIgnoredStrictOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            #importOrder,
            1,
            "expected resident-disabled refreshes to still respect in-flight budgeting instead of undercounting to zero"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "guarded_pause",
            "expected the strict in-flight budget to pause the refresh pass"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailLastPauseReason"),
            "budget",
            "expected the paused refresh pass to report a budget reason"
        )

        importOrder = {}
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local manualPauseManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "manual_pause_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 16,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local manualPauseOptions = {
            worldRootName = "StreamingPriorityManualPauseWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 128,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        MemoryGuardrail.New = function(config)
            local guardrail = originalMemoryGuardrailNew(config)
            guardrail:Pause("operator")
            return guardrail
        end

        StreamingService.Start(manualPauseManifest, manualPauseOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            #importOrder,
            0,
            "expected a manually paused scheduler not to admit work during telemetry refresh cycles"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "guarded_pause",
            "expected manual scheduler pauses to remain guarded_pause"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailLastPauseReason"),
            "operator",
            "expected manual scheduler pauses to preserve their caller-supplied reason"
        )
        MemoryGuardrail.New = originalMemoryGuardrailNew

        importOrder = {}
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local restartManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "restart_loaded",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    estimatedMemoryCost = 90,
                },
                {
                    id = "restart_candidate",
                    originStuds = { x = 220, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 20,
                },
            },
            GetChunk = function(_, chunkId)
                if chunkId == "restart_loaded" then
                    return makeChunk(chunkId, 0)
                end
                return makeChunk(chunkId, 220)
            end,
        }
        local restartWarmOptions = {
            worldRootName = "StreamingPriorityRestartWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 100,
                HighDetailRadius = 100,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 200,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }
        local restartStrictOptions = {
            worldRootName = "StreamingPriorityRestartWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 100,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(restartManifest, restartWarmOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(#importOrder, 1, "expected the warm restart pass to load only the near resident chunk")

        StreamingService.Stop()
        StreamingService.Start(restartManifest, restartStrictOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            #importOrder,
            1,
            "expected restart-time resident accounting to prevent a new admission that would exceed the budget"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            90,
            "expected restart telemetry to re-seed resident estimated cost from already loaded chunks"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "guarded_pause",
            "expected the restarted scheduler to pause when resident pressure leaves no room for the candidate chunk"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local partialRestartManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "restart_partial",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    subplans = {
                        {
                            id = "roads_west",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 20,
                        },
                        {
                            id = "roads_east",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 25,
                        },
                    },
                },
            },
            GetChunk = function(_, chunkId)
                return {
                    id = chunkId,
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {
                        {
                            id = "restart_road_west",
                            kind = "secondary",
                            widthStuds = 16,
                            points = {
                                { x = 12, y = 0, z = 36 },
                                { x = 48, y = 0, z = 36 },
                            },
                        },
                        {
                            id = "restart_road_east",
                            kind = "secondary",
                            widthStuds = 16,
                            points = {
                                { x = 52, y = 0, z = 64 },
                                { x = 88, y = 0, z = 64 },
                            },
                        },
                    },
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                    subplans = {
                        {
                            id = "roads_west",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 20,
                        },
                        {
                            id = "roads_east",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 25,
                        },
                    },
                }
            end,
        }
        local partialRestartOptions = {
            worldRootName = "StreamingPriorityPartialRestartWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                StreamingMaxWorkItemsPerUpdate = 1,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                SubplanRollout = {
                    Enabled = true,
                    AllowedLayers = {},
                    AllowedChunkIds = {},
                },
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 100,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        local partialRestartStartCount = subplanImportCount
        StreamingService.Start(partialRestartManifest, partialRestartOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - partialRestartStartCount,
            1,
            "expected the warm partial-restart pass to import only the first subplan under the per-update budget"
        )
        Assert.equal(
            subplanImportOrder[1],
            "roads_west",
            "expected the warm partial-restart pass to import the first sibling subplan deterministically"
        )

        StreamingService.Stop()
        StreamingService.Start(partialRestartManifest, partialRestartOptions)
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            20,
            "expected restart telemetry to preserve resident accounting for the already imported partial layer work item instead of dropping to zero or falling back to whole-chunk cost"
        )
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - partialRestartStartCount,
            2,
            "expected the restarted scheduler to admit only the remaining sibling subplan instead of reimporting completed work"
        )
        Assert.equal(
            subplanImportOrder[2],
            "roads_east",
            "expected the restarted scheduler to continue from the next pending sibling subplan"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            45,
            "expected resident telemetry to reflect both sibling subplans after restart finishes the chunk"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()
        ImportService.ResetSubplanState("restart_partial", partialRestartOptions.worldRootName)

        local restartCadenceStartCount = subplanImportCount
        StreamingService.Start(partialRestartManifest, partialRestartOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - restartCadenceStartCount,
            1,
            "expected the cadence baseline pass to import exactly one sibling subplan"
        )

        StreamingService.Stop()
        task.wait(0.3)
        StreamingService.Start(partialRestartManifest, partialRestartOptions)
        task.wait(0.1)
        Assert.equal(
            subplanImportCount - restartCadenceStartCount,
            1,
            "expected restart heartbeat cadence to remain idle until an explicit update call"
        )

        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - restartCadenceStartCount,
            2,
            "expected the explicit restart update to import the deferred sibling subplan"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local chunkEstimateSplitManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "chunk_estimate_split",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    estimatedMemoryCost = 64,
                    subplans = {
                        {
                            id = "roads_west",
                            layer = "roads",
                            featureCount = 1,
                        },
                        {
                            id = "roads_east",
                            layer = "roads",
                            featureCount = 1,
                        },
                    },
                },
            },
            GetChunk = function(_, chunkId)
                return {
                    id = chunkId,
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {
                        {
                            id = "chunk_estimate_road_west",
                            kind = "secondary",
                            widthStuds = 16,
                            points = {
                                { x = 12, y = 0, z = 36 },
                                { x = 48, y = 0, z = 36 },
                            },
                        },
                        {
                            id = "chunk_estimate_road_east",
                            kind = "secondary",
                            widthStuds = 16,
                            points = {
                                { x = 52, y = 0, z = 64 },
                                { x = 88, y = 0, z = 64 },
                            },
                        },
                    },
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                    subplans = {
                        {
                            id = "roads_west",
                            layer = "roads",
                            featureCount = 1,
                        },
                        {
                            id = "roads_east",
                            layer = "roads",
                            featureCount = 1,
                        },
                    },
                }
            end,
        }
        local chunkEstimateSplitOptions = {
            worldRootName = "StreamingPriorityChunkEstimateSplitWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                StreamingMaxWorkItemsPerUpdate = 1,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                SubplanRollout = {
                    Enabled = true,
                    AllowedLayers = {},
                    AllowedChunkIds = {},
                },
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 80,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        local chunkEstimateSplitStartCount = subplanImportCount
        StreamingService.Start(chunkEstimateSplitManifest, chunkEstimateSplitOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - chunkEstimateSplitStartCount,
            2,
            "expected chunk-level memory estimates to be split across sibling subplans instead of charging the full chunk twice"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            64,
            "expected resident telemetry to converge on the original chunk-level estimate after both sibling subplans load"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "active",
            "expected balanced sibling subplan cost sharing to avoid a false guarded pause"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local staleStateWarmManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "state_reuse_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    subplans = {
                        {
                            id = "roads_west",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 18,
                        },
                        {
                            id = "roads_east",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 18,
                        },
                    },
                },
            },
            GetChunk = function(_, chunkId)
                return {
                    id = chunkId,
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {
                        {
                            id = "state_reuse_road_west",
                            kind = "secondary",
                            widthStuds = 16,
                            points = {
                                { x = 12, y = 0, z = 36 },
                                { x = 48, y = 0, z = 36 },
                            },
                        },
                        {
                            id = "state_reuse_road_east",
                            kind = "secondary",
                            widthStuds = 16,
                            points = {
                                { x = 52, y = 0, z = 64 },
                                { x = 88, y = 0, z = 64 },
                            },
                        },
                    },
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                    subplans = {
                        {
                            id = "roads_west",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 18,
                        },
                        {
                            id = "roads_east",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 18,
                        },
                    },
                }
            end,
        }
        local staleStateRestartManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "state_reuse_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    subplans = {
                        {
                            id = "roads_rebuilt",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 18,
                        },
                    },
                },
            },
            GetChunk = function(_, chunkId)
                return {
                    id = chunkId,
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {
                        {
                            id = "state_reuse_road_rebuilt",
                            kind = "secondary",
                            widthStuds = 16,
                            points = {
                                { x = 18, y = 0, z = 50 },
                                { x = 82, y = 0, z = 50 },
                            },
                        },
                    },
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                    subplans = {
                        {
                            id = "roads_rebuilt",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 18,
                        },
                    },
                }
            end,
        }
        local staleStateOptions = {
            worldRootName = "StreamingPriorityStateReuseWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                StreamingMaxWorkItemsPerUpdate = 1,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                SubplanRollout = {
                    Enabled = true,
                    AllowedLayers = {},
                    AllowedChunkIds = {},
                },
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 100,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        local staleStateStartCount = subplanImportCount
        StreamingService.Start(staleStateWarmManifest, staleStateOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - staleStateStartCount,
            1,
            "expected the warm stale-state pass to import exactly one sibling subplan"
        )

        StreamingService.Stop()
        ChunkLoader.Clear()
        StreamingService.Start(staleStateRestartManifest, staleStateOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - staleStateStartCount,
            2,
            "expected start-up state pruning to allow a rebuilt chunk with the same id to import fresh work after a clear"
        )
        Assert.equal(
            subplanImportOrder[#subplanImportOrder],
            "roads_rebuilt",
            "expected reused chunk ids to import the new subplan definition instead of carrying stale completion state across sessions"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local staleRecoveryOptions = {
            worldRootName = "StreamingPriorityStaleSubplanRecoveryWorld",
            config = staleStateOptions.config,
            preferredLookVector = Vector3.new(1, 0, 0),
        }
        local staleRecoveryStartCount = subplanImportCount
        StreamingService.Start(staleStateWarmManifest, staleRecoveryOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - staleRecoveryStartCount,
            2,
            "expected the warm stale-recovery pass to import both sibling subplans across two updates"
        )
        local staleRecoveryWorldRoot = Workspace:FindFirstChild(staleRecoveryOptions.worldRootName)
        local staleRecoveryChunkFolder = staleRecoveryWorldRoot
                and staleRecoveryWorldRoot:FindFirstChild("state_reuse_chunk")
            or nil
        if staleRecoveryChunkFolder ~= nil then
            staleRecoveryChunkFolder:Destroy()
        end
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - staleRecoveryStartCount,
            4,
            "expected same-session stale chunk recovery to clear completed subplan state and reimport every sibling subplan"
        )
        Assert.equal(
            subplanImportOrder[#subplanImportOrder - 1],
            "roads_west",
            "expected same-session stale chunk recovery to restart sibling subplan imports from the first subplan"
        )
        Assert.equal(
            subplanImportOrder[#subplanImportOrder],
            "roads_east",
            "expected same-session stale chunk recovery to reimport the remaining sibling subplan instead of preserving stale completion state"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local manifestSwitchWarm = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "switch_old_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 60,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local manifestSwitchNext = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "switch_new_chunk",
                    originStuds = { x = 120, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 20,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 120)
            end,
        }
        local manifestSwitchOptions = {
            worldRootName = "StreamingPriorityManifestSwitchWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 70,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(manifestSwitchWarm, manifestSwitchOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            ChunkLoader.GetChunkEntry("switch_old_chunk", manifestSwitchOptions.worldRootName) ~= nil,
            true,
            "expected the warm manifest-switch pass to leave the old chunk loaded"
        )

        StreamingService.Stop()
        StreamingService.Start(manifestSwitchNext, manifestSwitchOptions)
        Assert.equal(
            ChunkLoader.GetChunkEntry("switch_old_chunk", manifestSwitchOptions.worldRootName),
            nil,
            "expected startup reconciliation to unload loaded chunks that are not present in the next manifest"
        )
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            importOrder[#importOrder],
            "switch_new_chunk",
            "expected the next manifest to import its new chunk after orphaned residency is reconciled"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            20,
            "expected resident telemetry to track only the surviving manifest chunk after start-up reconciliation"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local sameIdWarmManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "same_id_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 20,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local sameIdRevisedManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "same_id_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    estimatedMemoryCost = 35,
                    subplans = {
                        {
                            id = "roads_revised",
                            layer = "roads",
                            featureCount = 2,
                            streamingCost = 35,
                        },
                    },
                },
            },
            GetChunk = function(_, chunkId)
                return {
                    id = chunkId,
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {
                        {
                            id = "same_id_revised_road",
                            kind = "secondary",
                            widthStuds = 18,
                            points = {
                                { x = 10, y = 0, z = 50 },
                                { x = 90, y = 0, z = 50 },
                            },
                        },
                    },
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                    subplans = {
                        {
                            id = "roads_revised",
                            layer = "roads",
                            featureCount = 2,
                            streamingCost = 35,
                        },
                    },
                }
            end,
        }
        local sameIdOptions = {
            worldRootName = "StreamingPrioritySameIdRevisionWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                SubplanRollout = {
                    Enabled = true,
                    AllowedLayers = {},
                    AllowedChunkIds = {},
                },
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 100,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(sameIdWarmManifest, sameIdOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            ChunkLoader.GetChunkEntry("same_id_chunk", sameIdOptions.worldRootName) ~= nil,
            true,
            "expected the warm same-id revision pass to load the initial chunk"
        )

        StreamingService.Stop()
        StreamingService.Start(sameIdRevisedManifest, sameIdOptions)
        Assert.equal(
            ChunkLoader.GetChunkEntry("same_id_chunk", sameIdOptions.worldRootName),
            nil,
            "expected same-id manifest revisions to force startup reconciliation instead of preserving stale loaded content"
        )
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            importOrder[#importOrder],
            "same_id_chunk",
            "expected the revised same-id manifest to reimport the chunk after reconciliation"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            35,
            "expected resident telemetry to reflect the revised same-id manifest cost after reimport"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local partitionSignatureWarmManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "partition_signature_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    partitionVersion = 1,
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 24,
                    subplans = {
                        {
                            id = "roads_core",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 24,
                            bounds = {
                                minX = 0,
                                minY = 0,
                                maxX = 48,
                                maxY = 48,
                            },
                        },
                    },
                },
            },
            GetChunk = function(_, chunkId)
                return {
                    id = chunkId,
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {
                        {
                            id = "partition_signature_road",
                            kind = "secondary",
                            widthStuds = 18,
                            points = {
                                { x = 10, y = 0, z = 50 },
                                { x = 90, y = 0, z = 50 },
                            },
                        },
                    },
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                    subplans = {
                        {
                            id = "roads_core",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 24,
                            bounds = {
                                minX = 0,
                                minY = 0,
                                maxX = 48,
                                maxY = 48,
                            },
                        },
                    },
                }
            end,
        }
        local partitionSignatureRevisedManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "partition_signature_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    partitionVersion = 2,
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 24,
                    subplans = {
                        {
                            id = "roads_core",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 24,
                            bounds = {
                                minX = 24,
                                minY = 24,
                                maxX = 72,
                                maxY = 72,
                            },
                        },
                    },
                },
            },
            GetChunk = partitionSignatureWarmManifest.GetChunk,
        }
        local partitionSignatureOptions = {
            worldRootName = "StreamingPriorityPartitionSignatureWorld",
            config = sameIdOptions.config,
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        local partitionSignatureStartCount = subplanImportCount
        StreamingService.Start(partitionSignatureWarmManifest, partitionSignatureOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - partitionSignatureStartCount,
            1,
            "expected the warm partition-signature pass to import the initial subplan once"
        )

        StreamingService.Stop()
        StreamingService.Start(partitionSignatureRevisedManifest, partitionSignatureOptions)
        Assert.equal(
            ChunkLoader.GetChunkEntry("partition_signature_chunk", partitionSignatureOptions.worldRootName),
            nil,
            "expected startup reconciliation to unload same-id chunks when only partitionVersion or bounds changed"
        )
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            subplanImportCount - partitionSignatureStartCount,
            2,
            "expected partition-signature changes to force a fresh subplan import on restart"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local restartOutOfRangeManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "restart_out_of_range",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 24,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local restartOutOfRangeOptions = {
            worldRootName = "StreamingPriorityRestartOutOfRangeWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 200,
                HighDetailRadius = 200,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 100,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(restartOutOfRangeManifest, restartOutOfRangeOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            ChunkLoader.GetChunkEntry("restart_out_of_range", restartOutOfRangeOptions.worldRootName) ~= nil,
            true,
            "expected the warm restart-out-of-range pass to load the chunk"
        )

        StreamingService.Stop()
        StreamingService.Start(restartOutOfRangeManifest, restartOutOfRangeOptions)
        StreamingService.Update(Vector3.new(2000, 0, 0))
        Assert.equal(
            ChunkLoader.GetChunkEntry("restart_out_of_range", restartOutOfRangeOptions.worldRootName),
            nil,
            "expected restarted streaming to unload surviving chunks that are outside the resumed focal radius"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            0,
            "expected resident telemetry to clear after the resumed unload removes an out-of-range chunk"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local disjointStateWarmManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "disjoint_old_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    subplans = {
                        {
                            id = "roads_west",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 12,
                        },
                        {
                            id = "roads_east",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 12,
                        },
                    },
                },
            },
            GetChunk = staleStateWarmManifest.GetChunk,
        }
        local disjointStateNextManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "disjoint_new_chunk",
                    originStuds = { x = 120, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 12,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 120)
            end,
        }
        local disjointStateOptions = {
            worldRootName = "StreamingPriorityDisjointStateWorld",
            config = staleStateOptions.config,
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(disjointStateWarmManifest, disjointStateOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        ChunkLoader.Clear()
        StreamingService.Start(disjointStateNextManifest, disjointStateOptions)
        Assert.equal(
            next(
                ImportService.GetSubplanState("disjoint_old_chunk", disjointStateOptions.worldRootName).completedWorkItems
            ),
            nil,
            "expected a disjoint session restart with no loaded chunks to clear stale importer subplan state for the active world root"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local rootScopedStateManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "shared_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    subplans = {
                        {
                            id = "roads_shared",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 16,
                        },
                    },
                },
            },
            GetChunk = function(_, chunkId)
                return {
                    id = chunkId,
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {
                        {
                            id = "shared_road",
                            kind = "secondary",
                            widthStuds = 18,
                            points = {
                                { x = 0, y = 0, z = 50 },
                                { x = 100, y = 0, z = 50 },
                            },
                        },
                    },
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                    subplans = {
                        {
                            id = "roads_shared",
                            layer = "roads",
                            featureCount = 1,
                            streamingCost = 16,
                        },
                    },
                }
            end,
        }
        local rootScopedStateOptionsA = {
            worldRootName = "StreamingPriorityRootScopedStateWorldA",
            config = staleStateOptions.config,
            preferredLookVector = Vector3.new(1, 0, 0),
        }
        local rootScopedStateOptionsB = {
            worldRootName = "StreamingPriorityRootScopedStateWorldB",
            config = staleStateOptions.config,
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(rootScopedStateManifest, rootScopedStateOptionsA)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        StreamingService.Start({
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {},
            GetChunk = function()
                return nil
            end,
        }, rootScopedStateOptionsB)
        Assert.truthy(
            next(
                ImportService.GetSubplanState("shared_chunk", rootScopedStateOptionsA.worldRootName).completedWorkItems
            ) ~= nil,
            "expected starting an empty second world root not to wipe subplan completion state for another root"
        )
        StreamingService.Stop()

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local defaultRootScopedOptions = {
            config = staleStateOptions.config,
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(rootScopedStateManifest, rootScopedStateOptionsA)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        StreamingService.Start({
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {},
            GetChunk = function()
                return nil
            end,
        }, defaultRootScopedOptions)
        Assert.truthy(
            next(
                ImportService.GetSubplanState("shared_chunk", rootScopedStateOptionsA.worldRootName).completedWorkItems
            ) ~= nil,
            "expected starting an empty default-root session not to wipe subplan completion state for another explicit root"
        )
        StreamingService.Stop()

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        StreamingService.Start(rootScopedStateManifest, defaultRootScopedOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        StreamingService.Start({
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {},
            GetChunk = function()
                return nil
            end,
        }, rootScopedStateOptionsB)
        Assert.truthy(
            next(ImportService.GetSubplanState("shared_chunk").completedWorkItems) ~= nil,
            "expected starting an empty explicit-root session not to wipe subplan completion state for the default GeneratedWorld root"
        )
        StreamingService.Stop()

        StreamingService.Start(rootScopedStateManifest, defaultRootScopedOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        StreamingService.Start(rootScopedStateManifest, rootScopedStateOptionsA)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        local legacyNoArgEntry = ChunkLoader.GetChunkEntry("shared_chunk")
        Assert.equal(
            legacyNoArgEntry and legacyNoArgEntry.worldRootName or nil,
            "GeneratedWorld",
            "expected no-arg ChunkLoader lookups to prefer the default GeneratedWorld entry when duplicate chunk ids exist across roots"
        )
        Assert.equal(
            (function()
                local sharedChunkCount = 0
                for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks()) do
                    if chunkId == "shared_chunk" then
                        sharedChunkCount += 1
                    end
                end
                return sharedChunkCount
            end)(),
            1,
            "expected no-arg loaded chunk enumeration to collapse duplicate shared_chunk ids across roots"
        )
        ChunkLoader.UnloadChunk("shared_chunk")
        Assert.equal(
            ChunkLoader.GetChunkEntry("shared_chunk") and ChunkLoader.GetChunkEntry("shared_chunk").worldRootName or nil,
            rootScopedStateOptionsA.worldRootName,
            "expected a no-arg unload to remove the default GeneratedWorld entry and fall back to the remaining explicit-root copy"
        )
        Assert.equal(
            ChunkLoader.GetChunkEntry("shared_chunk", rootScopedStateOptionsA.worldRootName) ~= nil,
            true,
            "expected a no-arg unload not to destroy an explicit-root entry that happens to reuse the same chunk id"
        )

        ChunkLoader.Clear()
        StreamingService.Stop()
        StreamingService.Start(rootScopedStateManifest, defaultRootScopedOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        StreamingService.Start(rootScopedStateManifest, rootScopedStateOptionsA)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        local staleDefaultWorldRoot = Workspace:FindFirstChild("GeneratedWorld")
        local staleDefaultContainer = Instance.new("Folder")
        staleDefaultContainer.Name = "StaleDefaultWorldContainer"
        if staleDefaultWorldRoot ~= nil then
            staleDefaultWorldRoot.Parent = staleDefaultContainer
        end
        ChunkLoader.UnloadChunk("shared_chunk")
        Assert.equal(
            ChunkLoader.GetChunkEntry("shared_chunk", rootScopedStateOptionsA.worldRootName),
            nil,
            "expected a no-arg unload to fall through to the live explicit-root entry when the default-root copy is stale"
        )
        staleDefaultContainer:Destroy()

        ChunkLoader.Clear()
        StreamingService.Stop()
        local rootScopedStateOptionsZero = {
            worldRootName = "StreamingPriorityRootScopedStateWorld0",
            config = staleStateOptions.config,
            preferredLookVector = Vector3.new(1, 0, 0),
        }
        StreamingService.Start(rootScopedStateManifest, rootScopedStateOptionsZero)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        StreamingService.Start(rootScopedStateManifest, rootScopedStateOptionsA)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Stop()
        local staleExplicitWorldRoot = Workspace:FindFirstChild(rootScopedStateOptionsZero.worldRootName)
        local staleExplicitContainer = Instance.new("Folder")
        staleExplicitContainer.Name = "StaleExplicitWorldContainer"
        if staleExplicitWorldRoot ~= nil then
            staleExplicitWorldRoot.Parent = staleExplicitContainer
        end
        ChunkLoader.UnloadChunk("shared_chunk")
        Assert.equal(
            ChunkLoader.GetChunkEntry("shared_chunk", rootScopedStateOptionsA.worldRootName),
            nil,
            "expected a no-arg unload to skip stale explicit-root entries and unload the first live explicit-root copy"
        )
        staleExplicitContainer:Destroy()

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local detachedFolderManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "detached_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 24,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local detachedFolderOptions = {
            worldRootName = "StreamingPriorityDetachedFolderWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                SubplanRollout = {
                    Enabled = true,
                    AllowedLayers = {},
                    AllowedChunkIds = {},
                },
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 24,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(detachedFolderManifest, detachedFolderOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            ChunkLoader.GetChunkEntry("detached_chunk", detachedFolderOptions.worldRootName) ~= nil,
            true,
            "expected the warm detached-folder pass to load the initial chunk"
        )
        local detachedWorldRoot = Workspace:FindFirstChild(detachedFolderOptions.worldRootName)
        local detachedChunkFolder = detachedWorldRoot and detachedWorldRoot:FindFirstChild("detached_chunk") or nil
        local detachedWarmImportCount = #importOrder
        if detachedChunkFolder ~= nil then
            detachedChunkFolder:Destroy()
        end

        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            #importOrder - detachedWarmImportCount,
            1,
            "expected a destroyed chunk folder to be treated as unloaded and reimported during the same streaming session"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            24,
            "expected same-session stale chunk recovery to shed stale resident cost before reimporting under a tight guardrail budget"
        )
        StreamingService.Stop()

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        StreamingService.Start(detachedFolderManifest, detachedFolderOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        local detachedWorldRootContainer = Instance.new("Folder")
        detachedWorldRootContainer.Name = "DetachedWorldRootContainer"
        local detachedWorldRootForReparent = Workspace:FindFirstChild(detachedFolderOptions.worldRootName)
        local detachedReparentWarmImportCount = #importOrder
        if detachedWorldRootForReparent ~= nil then
            detachedWorldRootForReparent.Parent = detachedWorldRootContainer
        end
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            #importOrder - detachedReparentWarmImportCount,
            1,
            "expected a chunk under a world root detached from Workspace to be treated as stale and reimported during the same streaming session"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            24,
            "expected detaching the world root from Workspace to clear stale resident bytes before same-session reimport"
        )
        StreamingService.Stop()
        detachedWorldRootContainer:Destroy()

        local cancelledManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "cancelled_chunk",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 1,
                    estimatedMemoryCost = 32,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local cancelledOptions = {
            worldRootName = "StreamingPriorityCancelledWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 100,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = true,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }
        local wrappedImportChunk = ImportService.ImportChunk
        ImportService.ImportChunk = function(chunk, importOptions)
            local worldRoot = Workspace:FindFirstChild(importOptions.worldRootName)
            if worldRoot == nil then
                worldRoot = Instance.new("Folder")
                worldRoot.Name = importOptions.worldRootName
                worldRoot.Parent = Workspace
            end
            local chunkFolder = Instance.new("Folder")
            chunkFolder.Name = chunk.id
            chunkFolder.Parent = worldRoot
            local partialPart = Instance.new("Part")
            partialPart.Name = "CancelledPartial"
            partialPart.Parent = chunkFolder
            return nil
        end

        StreamingService.Start(cancelledManifest, cancelledOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            ChunkLoader.GetChunkEntry("cancelled_chunk", cancelledOptions.worldRootName),
            nil,
            "expected cancelled imports not to leave phantom loaded chunks behind"
        )
        local cancelledWorldRoot = Workspace:FindFirstChild(cancelledOptions.worldRootName)
        local cancelledChunkFolder = cancelledWorldRoot and cancelledWorldRoot:FindFirstChild("cancelled_chunk") or nil
        Assert.equal(
            cancelledChunkFolder and #cancelledChunkFolder:GetChildren() or 0,
            0,
            "expected cancelled imports to roll back partial scene mutations instead of leaving stray children behind"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            0,
            "expected cancelled imports not to record resident guardrail cost"
        )

        ImportService.ImportChunk = wrappedImportChunk
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            importOrder[#importOrder],
            "cancelled_chunk",
            "expected the next update to retry a cancelled chunk instead of believing it already loaded"
        )

        importOrder = {}
        table.clear(subplanImportOrder)
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local disabledCostManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "inflight_telemetry_disabled",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    estimatedMemoryCost = 64,
                },
            },
            GetChunk = function(_, chunkId)
                return makeChunk(chunkId, 0)
            end,
        }
        local disabledCostOptions = {
            worldRootName = "StreamingPriorityDisabledCostWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 256,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = true,
                    CountInFlightCost = false,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(disabledCostManifest, disabledCostOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))

        Assert.equal(#importOrder, 1, "expected disabled in-flight accounting to still admit the chunk")
        Assert.equal(
            capturedInFlightTelemetryDuringImport["inflight_telemetry_disabled"],
            0,
            "expected in-flight telemetry to stay aligned with effective admission accounting when CountInFlightCost is false"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailInFlightEstimatedCost"),
            0,
            "expected published in-flight telemetry to remain zero after import when CountInFlightCost is false"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            64,
            "expected resident telemetry to continue reflecting effective resident accounting when resident cost remains enabled"
        )

        importOrder = {}
        table.clear(capturedInFlightTelemetryDuringImport)
        clearMemoryGuardrailAttrs()
        ChunkLoader.Clear()
        StreamingService.Stop()

        local disabledResidentManifest = {
            schemaVersion = "0.4.0",
            meta = manifest.meta,
            chunkRefs = {
                {
                    id = "resident_disabled_a",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    estimatedMemoryCost = 64,
                },
                {
                    id = "resident_disabled_b",
                    originStuds = { x = 120, y = 0, z = 0 },
                    shards = { "fake" },
                    featureCount = 2,
                    estimatedMemoryCost = 64,
                },
            },
            GetChunk = function(_, chunkId)
                if chunkId == "resident_disabled_a" then
                    return makeChunk(chunkId, 0)
                end
                return makeChunk(chunkId, 120)
            end,
        }
        local disabledResidentOptions = {
            worldRootName = "StreamingPriorityResidentDisabledWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "mesh",
                LanduseMode = "fill",
                MemoryGuardrails = {
                    Enabled = true,
                    EstimatedBudgetBytes = 32,
                    ResumeBudgetRatio = 0.85,
                    CountResidentChunkCost = false,
                    CountInFlightCost = false,
                    HostProbe = {
                        Enabled = false,
                    },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        }

        StreamingService.Start(disabledResidentManifest, disabledResidentOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))

        Assert.equal(
            #importOrder,
            2,
            "expected disabling resident and in-flight accounting to keep admission aligned with the zeroed effective guardrail costs"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailResidentEstimatedCost"),
            0,
            "expected resident telemetry to stay aligned with effective accounting when CountResidentChunkCost is false"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailInFlightEstimatedCost"),
            0,
            "expected in-flight telemetry to stay aligned with effective accounting when both cost branches are disabled"
        )
        Assert.equal(
            Workspace:GetAttribute("ArnisStreamingMemoryGuardrailState"),
            "active",
            "expected the guardrail to remain active when both resident and in-flight accounting are disabled"
        )
    end, debug.traceback)

    ImportService.ImportChunk = originalImportChunk
    ImportService.ImportChunkSubplan = originalImportChunkSubplan
    MemoryGuardrail.New = originalMemoryGuardrailNew
    StreamingService.Stop()
    local worldRoot = Workspace:FindFirstChild("StreamingPriorityWorld")
    if worldRoot then
        worldRoot:Destroy()
    end
    local guardrailWorldRoot = Workspace:FindFirstChild("StreamingPriorityGuardrailWorld")
    if guardrailWorldRoot then
        guardrailWorldRoot:Destroy()
    end
    local disabledCostWorldRoot = Workspace:FindFirstChild("StreamingPriorityDisabledCostWorld")
    if disabledCostWorldRoot then
        disabledCostWorldRoot:Destroy()
    end
    local replacementWorldRoot = Workspace:FindFirstChild("StreamingPriorityReplacementWorld")
    if replacementWorldRoot then
        replacementWorldRoot:Destroy()
    end
    local manualPauseWorldRoot = Workspace:FindFirstChild("StreamingPriorityManualPauseWorld")
    if manualPauseWorldRoot then
        manualPauseWorldRoot:Destroy()
    end
    local restartWorldRoot = Workspace:FindFirstChild("StreamingPriorityRestartWorld")
    if restartWorldRoot then
        restartWorldRoot:Destroy()
    end
    local partialRestartWorldRoot = Workspace:FindFirstChild("StreamingPriorityPartialRestartWorld")
    if partialRestartWorldRoot then
        partialRestartWorldRoot:Destroy()
    end
    local chunkEstimateSplitWorldRoot = Workspace:FindFirstChild("StreamingPriorityChunkEstimateSplitWorld")
    if chunkEstimateSplitWorldRoot then
        chunkEstimateSplitWorldRoot:Destroy()
    end
    local staleStateWorldRoot = Workspace:FindFirstChild("StreamingPriorityStateReuseWorld")
    if staleStateWorldRoot then
        staleStateWorldRoot:Destroy()
    end
    local staleRecoveryWorldRoot = Workspace:FindFirstChild("StreamingPriorityStaleSubplanRecoveryWorld")
    if staleRecoveryWorldRoot then
        staleRecoveryWorldRoot:Destroy()
    end
    local manifestSwitchWorldRoot = Workspace:FindFirstChild("StreamingPriorityManifestSwitchWorld")
    if manifestSwitchWorldRoot then
        manifestSwitchWorldRoot:Destroy()
    end
    local sameIdRevisionWorldRoot = Workspace:FindFirstChild("StreamingPrioritySameIdRevisionWorld")
    if sameIdRevisionWorldRoot then
        sameIdRevisionWorldRoot:Destroy()
    end
    local partitionSignatureWorldRoot = Workspace:FindFirstChild("StreamingPriorityPartitionSignatureWorld")
    if partitionSignatureWorldRoot then
        partitionSignatureWorldRoot:Destroy()
    end
    local restartOutOfRangeWorldRoot = Workspace:FindFirstChild("StreamingPriorityRestartOutOfRangeWorld")
    if restartOutOfRangeWorldRoot then
        restartOutOfRangeWorldRoot:Destroy()
    end
    local disjointStateWorldRoot = Workspace:FindFirstChild("StreamingPriorityDisjointStateWorld")
    if disjointStateWorldRoot then
        disjointStateWorldRoot:Destroy()
    end
    local rootScopedStateWorldA = Workspace:FindFirstChild("StreamingPriorityRootScopedStateWorldA")
    if rootScopedStateWorldA then
        rootScopedStateWorldA:Destroy()
    end
    local rootScopedStateWorld0 = Workspace:FindFirstChild("StreamingPriorityRootScopedStateWorld0")
    if rootScopedStateWorld0 then
        rootScopedStateWorld0:Destroy()
    end
    local rootScopedStateWorldB = Workspace:FindFirstChild("StreamingPriorityRootScopedStateWorldB")
    if rootScopedStateWorldB then
        rootScopedStateWorldB:Destroy()
    end
    local detachedFolderWorldRoot = Workspace:FindFirstChild("StreamingPriorityDetachedFolderWorld")
    if detachedFolderWorldRoot then
        detachedFolderWorldRoot:Destroy()
    end
    local detachedWorldRootContainer = Workspace:FindFirstChild("DetachedWorldRootContainer")
    if detachedWorldRootContainer then
        detachedWorldRootContainer:Destroy()
    end
    local cancelledWorldRoot = Workspace:FindFirstChild("StreamingPriorityCancelledWorld")
    if cancelledWorldRoot then
        cancelledWorldRoot:Destroy()
    end
    local residentIgnoredRefreshWorldRoot = Workspace:FindFirstChild("StreamingPriorityResidentIgnoredRefreshWorld")
    if residentIgnoredRefreshWorldRoot then
        residentIgnoredRefreshWorldRoot:Destroy()
    end
    local disabledResidentWorldRoot = Workspace:FindFirstChild("StreamingPriorityResidentDisabledWorld")
    if disabledResidentWorldRoot then
        disabledResidentWorldRoot:Destroy()
    end
    local generatedWorldRoot = Workspace:FindFirstChild("GeneratedWorld")
    if generatedWorldRoot then
        generatedWorldRoot:Destroy()
    end
    clearMemoryGuardrailAttrs()
    ChunkLoader.Clear()

    if not ok then
        error(err, 0)
    end
end
