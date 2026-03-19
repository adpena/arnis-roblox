return function()
    local PolygonBatcher = require(script.Parent.Parent.ImportService.PolygonBatcher)
    local Assert = require(script.Parent.Assert)

    local rects = PolygonBatcher.BuildRects({
        Vector3.new(0, 0, 0),
        Vector3.new(16, 0, 0),
        Vector3.new(16, 0, 8),
        Vector3.new(0, 0, 8),
    }, 4)
    Assert.equal(#rects, 1, "expected rectangle polygon to coalesce to one rect")
    Assert.near(rects[1].width, 16, 1e-6, "expected full rectangle width")
    Assert.near(rects[1].depth, 8, 1e-6, "expected full rectangle depth")

    local cellRects = PolygonBatcher.BuildRectsFromCells({
        { x = 2, z = 2 },
        { x = 6, z = 2 },
        { x = 2, z = 6 },
    }, 4)
    Assert.equal(#cellRects, 2, "expected L-shape cells to coalesce into two rects")
    local totalArea = 0
    for _, rect in ipairs(cellRects) do
        totalArea += rect.width * rect.depth
    end
    Assert.near(totalArea, 48, 1e-6, "expected coalesced cell area to match source cells")

    local rowRects = PolygonBatcher.BuildRectsFromRows({
        {
            z = 2,
            segments = {
                { x0 = 0, x1 = 8 },
            },
        },
        {
            z = 6,
            segments = {
                { x0 = 0, x1 = 8 },
            },
        },
    }, 4)
    Assert.equal(#rowRects, 1, "expected vertically identical rows to merge into one rect")
    Assert.near(rowRects[1].width, 8, 1e-6, "expected merged row rect width")
    Assert.near(rowRects[1].depth, 8, 1e-6, "expected merged row rect depth")

    local gridCells = PolygonBatcher.BuildGridCells({
        { x = 0, z = 0 },
        { x = 16, z = 0 },
        { x = 16, z = 8 },
        { x = 0, z = 8 },
    }, 4)
    Assert.equal(#gridCells, 8, "expected rectangle polygon to expand to exact scanline grid cells")
end
