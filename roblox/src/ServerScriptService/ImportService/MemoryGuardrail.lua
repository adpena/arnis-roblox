local MemoryGuardrail = {}
MemoryGuardrail.__index = MemoryGuardrail

local ACTIVE_STATE = "active"
local GUARDED_PAUSE_STATE = "guarded_pause"
local DEFAULT_RESUME_RATIO = 0.85

local function normalizeNonNegativeNumber(value)
    if type(value) ~= "number" or value < 0 then
        return 0
    end
    return value
end

local function normalizeOptionalNumber(value)
    if type(value) ~= "number" then
        return nil
    end
    return value
end

local function normalizeResumeRatio(value)
    if type(value) ~= "number" then
        return DEFAULT_RESUME_RATIO
    end

    if value ~= value then
        return DEFAULT_RESUME_RATIO
    end

    if value <= 0 then
        return DEFAULT_RESUME_RATIO
    end

    if value > 1 then
        return 1
    end

    return value
end

local function normalizeConfig(config)
    config = if type(config) == "table" then config else {}
    local hostProbe = if type(config.HostProbe) == "table" then config.HostProbe else {}

    return {
        Enabled = config.Enabled ~= false,
        EstimatedBudgetBytes = normalizeNonNegativeNumber(config.EstimatedBudgetBytes),
        ResumeBudgetRatio = normalizeResumeRatio(config.ResumeBudgetRatio),
        CountResidentChunkCost = config.CountResidentChunkCost ~= false,
        CountInFlightCost = config.CountInFlightCost ~= false,
        HostProbe = {
            Enabled = hostProbe.Enabled == true,
            CriticalAvailableBytes = normalizeOptionalNumber(hostProbe.CriticalAvailableBytes),
            CriticalPressureLevel = normalizeOptionalNumber(hostProbe.CriticalPressureLevel),
        },
    }
end

local function createSnapshot(self)
    return {
        enabled = self.config.Enabled,
        state = self.state,
        pauseReason = self.pauseReason,
        projectedUsageBytes = self.projectedUsageBytes,
        residentBytes = self.residentBytes,
        inFlightBytes = self.inFlightBytes,
        admittedInFlightBytes = self.admittedInFlightBytes,
        budgetBytes = self.config.EstimatedBudgetBytes,
        resumeThresholdBytes = self.config.EstimatedBudgetBytes * self.config.ResumeBudgetRatio,
        countResidentChunkCost = self.config.CountResidentChunkCost,
        countInFlightCost = self.config.CountInFlightCost,
        hostProbe = {
            enabled = self.config.HostProbe.Enabled,
            criticalAvailableBytes = self.config.HostProbe.CriticalAvailableBytes,
            criticalPressureLevel = self.config.HostProbe.CriticalPressureLevel,
            availableBytes = self.hostProbeAvailableBytes,
            pressureLevel = self.hostProbePressureLevel,
            critical = self.hostProbeCritical,
        },
    }
end

local function enterPausedState(self, reason)
    if self.state ~= GUARDED_PAUSE_STATE then
        self.state = GUARDED_PAUSE_STATE
        self.pauseReason = reason
        return true
    end

    if self.pauseReason == nil and reason ~= nil then
        self.pauseReason = reason
    end

    return false
end

function MemoryGuardrail.ResolveConfig(config)
    return normalizeConfig(config)
end

function MemoryGuardrail.New(config)
    local self = setmetatable({}, MemoryGuardrail)
    self.config = normalizeConfig(config)
    self.state = ACTIVE_STATE
    self.pauseReason = nil
    self.projectedUsageBytes = 0
    self.residentBytes = 0
    self.inFlightBytes = 0
    self.admittedInFlightBytes = 0
    self.hostProbeAvailableBytes = nil
    self.hostProbePressureLevel = nil
    self.hostProbeCritical = false
    return self
end

function MemoryGuardrail:GetConfig()
    return self.config
end

function MemoryGuardrail:GetCounters()
    return {
        projectedUsageBytes = self.projectedUsageBytes,
        residentBytes = self.residentBytes,
        inFlightBytes = self.inFlightBytes,
        admittedInFlightBytes = self.admittedInFlightBytes,
    }
end

function MemoryGuardrail:IsPaused()
    return self.state == GUARDED_PAUSE_STATE
end

function MemoryGuardrail:GetResumeThresholdBytes()
    return self.config.EstimatedBudgetBytes * self.config.ResumeBudgetRatio
end

function MemoryGuardrail:SetResidentBytes(bytes)
    self.residentBytes = normalizeNonNegativeNumber(bytes)
    return self
end

function MemoryGuardrail:SetProjectedUsageBytes(bytes)
    self.projectedUsageBytes = normalizeNonNegativeNumber(bytes)

    if not self.config.Enabled then
        self.state = ACTIVE_STATE
        self.pauseReason = nil
        return self
    end

    if self.hostProbeCritical then
        enterPausedState(self, "host_probe")
        return self
    end

    if self.projectedUsageBytes > self.config.EstimatedBudgetBytes then
        enterPausedState(self, "budget")
    end

    return self
end

function MemoryGuardrail:AdmitInFlightBytes(bytes)
    local amount = normalizeNonNegativeNumber(bytes)
    self.inFlightBytes += amount
    self.admittedInFlightBytes += amount
    return self
end

function MemoryGuardrail:CompleteInFlightBytes(bytes)
    local amount = normalizeNonNegativeNumber(bytes)
    self.inFlightBytes = math.max(0, self.inFlightBytes - amount)
    return self
end

function MemoryGuardrail:Pause(reason)
    if not self.config.Enabled then
        return false
    end

    self.state = GUARDED_PAUSE_STATE
    self.pauseReason = if reason ~= nil then reason else "manual"
    return true
end

function MemoryGuardrail:CanResume()
    if not self.config.Enabled then
        return true
    end

    if self.hostProbeCritical then
        return false
    end

    return self.projectedUsageBytes < self:GetResumeThresholdBytes()
end

function MemoryGuardrail:Resume()
    if not self:CanResume() then
        return false
    end

    self.state = ACTIVE_STATE
    self.pauseReason = nil
    return true
end

function MemoryGuardrail:ObserveHostProbe(sample)
    local hostProbe = self.config.HostProbe
    local availableBytes = nil
    local pressureLevel = nil
    local critical = false

    if type(sample) == "table" then
        availableBytes = normalizeOptionalNumber(sample.availableBytes)
        pressureLevel = normalizeOptionalNumber(sample.pressureLevel)
    end

    if hostProbe.Enabled then
        if
            hostProbe.CriticalAvailableBytes ~= nil
            and availableBytes ~= nil
            and availableBytes <= hostProbe.CriticalAvailableBytes
        then
            critical = true
        end

        if
            hostProbe.CriticalPressureLevel ~= nil
            and pressureLevel ~= nil
            and pressureLevel >= hostProbe.CriticalPressureLevel
        then
            critical = true
        end
    end

    self.hostProbeAvailableBytes = availableBytes
    self.hostProbePressureLevel = pressureLevel
    self.hostProbeCritical = critical

    if not self.config.Enabled then
        self.state = ACTIVE_STATE
        self.pauseReason = nil
        return self
    end

    if critical then
        enterPausedState(self, "host_probe")
    end

    return self
end

function MemoryGuardrail:Reevaluate()
    if not self.config.Enabled then
        self.state = ACTIVE_STATE
        self.pauseReason = nil
        return self
    end

    if self.hostProbeCritical then
        enterPausedState(self, "host_probe")
        return self
    end

    if self.projectedUsageBytes > self.config.EstimatedBudgetBytes then
        enterPausedState(self, "budget")
    end

    return self
end

function MemoryGuardrail:Snapshot()
    return createSnapshot(self)
end

return MemoryGuardrail
