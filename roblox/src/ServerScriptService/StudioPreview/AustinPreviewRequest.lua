local AustinPreviewRequest = {}

AustinPreviewRequest.MODE_PREVIEW = "preview"
AustinPreviewRequest.MODE_FULL_BAKE = "full_bake"

local FULL_BAKE_MODE_ALIASES = table.freeze({
    export = true,
    full = true,
    authoritative = true,
    full_bake = true,
})

function AustinPreviewRequest.Normalize(request)
    local mode = AustinPreviewRequest.MODE_PREVIEW
    local debugHelpers = false

    if type(request) == "table" then
        local requestedMode = request.mode or request.buildMode
        if type(requestedMode) == "string" and FULL_BAKE_MODE_ALIASES[requestedMode] == true then
            mode = AustinPreviewRequest.MODE_FULL_BAKE
        end

        debugHelpers = request.debugHelpers == true or request.showDebugHelpers == true
    end

    return {
        mode = mode,
        debugHelpers = debugHelpers,
    }
end

function AustinPreviewRequest.ResolveLoadRadius(request, defaultLoadRadius)
    local normalizedRequest = AustinPreviewRequest.Normalize(request)
    if normalizedRequest.mode == AustinPreviewRequest.MODE_FULL_BAKE then
        return nil
    end

    return defaultLoadRadius
end

function AustinPreviewRequest.SelectChunkIds(handle, focusPoint, request, defaultLoadRadius)
    local normalizedRequest = AustinPreviewRequest.Normalize(request)
    local loadRadius = AustinPreviewRequest.ResolveLoadRadius(normalizedRequest, defaultLoadRadius)
    return handle:GetChunkIdsWithinRadius(focusPoint, loadRadius), loadRadius
end

return AustinPreviewRequest
