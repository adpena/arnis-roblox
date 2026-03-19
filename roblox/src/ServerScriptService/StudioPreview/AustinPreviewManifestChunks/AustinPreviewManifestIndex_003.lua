local function mergeChunk(target, fragment)
    for key, value in pairs(fragment) do
        if type(value) == "table" then
            local existing = target[key]
            if existing == nil then
                existing = {}
                target[key] = existing
            end

            if #value > 0 then
                for _, item in ipairs(value) do
                    table.insert(existing, item)
                end
            else
                for nestedKey, nestedValue in pairs(value) do
                    existing[nestedKey] = nestedValue
                end
            end
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local fragments = {
    require(script.Parent.AustinPreviewManifestIndex_003_Terrain),
    require(script.Parent.AustinPreviewManifestIndex_003_Roads),
    require(script.Parent.AustinPreviewManifestIndex_003_Buildings),
    require(script.Parent.AustinPreviewManifestIndex_003_Details),
}

local mergedChunk = {}
for _, fragment in ipairs(fragments) do
    local chunk = fragment.chunks and fragment.chunks[1]
    if chunk then
        mergeChunk(mergedChunk, chunk)
    end
end

return {
    chunks = { mergedChunk },
}
