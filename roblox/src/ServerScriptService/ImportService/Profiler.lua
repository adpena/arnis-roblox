local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Shared.Logger)

local Profiler = {}

local sessions = {}

function Profiler.begin(label)
	local session = {
		label = label,
		startedAt = os.clock(),
		id = HttpService:GenerateGUID(false),
	}
	table.insert(sessions, session)
	return session
end

function Profiler.finish(session, extra)
	session.finishedAt = os.clock()
	session.elapsedMs = (session.finishedAt - session.startedAt) * 1000
	session.extra = extra

	Logger.info(
		session.label,
		("elapsedMs=%.3f"):format(session.elapsedMs),
		extra and ("extra=" .. HttpService:JSONEncode(extra)) or ""
	)

	return session.elapsedMs
end

function Profiler.getSessions()
	return sessions
end

function Profiler.clear()
	sessions = {}
end

function Profiler.generateReport()
	local report = {
		timestamp = os.time(),
		totalElapsedMs = 0,
		activities = {},
	}

	for _, session in ipairs(sessions) do
		if session.finishedAt then
			table.insert(report.activities, {
				label = session.label,
				elapsedMs = session.elapsedMs,
				extra = session.extra,
			})
			-- We only sum top-level ImportManifest if we want total, 
			-- but let's just provide the raw data for now.
		end
	end

	return report
end

function Profiler.printReport()
	local report = Profiler.generateReport()
	Logger.info("--- Performance Report ---")
	Logger.info(HttpService:JSONEncode(report))
	Logger.info("--------------------------")
end

return Profiler
