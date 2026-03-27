return function()
    local Assert = require(script.Parent.Assert)
    local AustinPreviewRequest = require(script.Parent.Parent.StudioPreview.AustinPreviewRequest)

    local defaultRequest = AustinPreviewRequest.Normalize(nil)
    Assert.equal(
        defaultRequest.mode,
        AustinPreviewRequest.MODE_PREVIEW,
        "expected nil request to default to preview mode"
    )
    Assert.equal(
        defaultRequest.debugHelpers,
        false,
        "expected nil request to keep preview helper geometry disabled by default"
    )

    local previewRequest = AustinPreviewRequest.Normalize({
        mode = "preview",
    })
    Assert.equal(
        previewRequest.mode,
        AustinPreviewRequest.MODE_PREVIEW,
        "expected explicit preview mode to stay preview"
    )
    Assert.equal(
        previewRequest.debugHelpers,
        false,
        "expected plain preview requests not to enable debug helper geometry"
    )

    local helperRequest = AustinPreviewRequest.Normalize({
        mode = "preview",
        debugHelpers = true,
    })
    Assert.equal(helperRequest.debugHelpers, true, "expected preview requests to opt into helper geometry explicitly")

    local exportRequest = AustinPreviewRequest.Normalize({
        mode = "export",
    })
    Assert.equal(
        exportRequest.mode,
        AustinPreviewRequest.MODE_FULL_BAKE,
        "expected export mode to normalize to authoritative full-bake mode"
    )

    local fullBakeRequest = AustinPreviewRequest.Normalize({
        mode = "full_bake",
    })
    Assert.equal(fullBakeRequest.mode, AustinPreviewRequest.MODE_FULL_BAKE, "expected full_bake mode to stay full_bake")

    local selectionCalls = {}
    local handle = {}

    function handle:GetChunkIdsWithinRadius(_focusPoint, radius)
        selectionCalls[#selectionCalls + 1] = if radius == nil then "full" else tostring(radius)
        if radius == nil then
            return { "0_0", "1_0", "2_0" }
        end
        return { "0_0", "1_0" }
    end

    local previewIds, previewRadius = AustinPreviewRequest.SelectChunkIds(handle, nil, { mode = "preview" }, 1024)
    Assert.equal(previewRadius, 1024, "expected preview requests to keep the default preview radius")
    Assert.equal(#previewIds, 2, "expected preview requests to keep radius-limited chunk selection")
    Assert.equal(selectionCalls[1], "1024", "expected preview requests to pass the preview radius to the handle")

    local fullBakeIds, fullBakeRadius = AustinPreviewRequest.SelectChunkIds(handle, nil, { mode = "full_bake" }, 1024)
    Assert.equal(fullBakeRadius, nil, "expected full-bake requests to clear the preview radius")
    Assert.equal(#fullBakeIds, 3, "expected full-bake requests to select all chunk ids")
    Assert.equal(selectionCalls[2], "full", "expected full-bake requests to use nil radius selection")

    local exportIds, exportRadius = AustinPreviewRequest.SelectChunkIds(handle, nil, { mode = "export" }, 1024)
    Assert.equal(exportRadius, nil, "expected export requests to inherit full-bake radius semantics")
    Assert.equal(#exportIds, 3, "expected export requests to select all chunk ids")
    Assert.equal(selectionCalls[3], "full", "expected export requests to use nil radius selection")
end
