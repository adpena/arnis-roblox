return function()
    local EditableImageCompat = require(script.Parent.Parent.ImportService.EditableImageCompat)
    local Assert = require(script.Parent.Assert)

    local sample = buffer.create(8)
    buffer.writeu8(sample, 0, 10)
    buffer.writeu8(sample, 1, 20)
    buffer.writeu8(sample, 2, 30)
    buffer.writeu8(sample, 3, 40)
    buffer.writeu8(sample, 4, 50)
    buffer.writeu8(sample, 5, 60)
    buffer.writeu8(sample, 6, 70)
    buffer.writeu8(sample, 7, 80)

    local bufferCall = nil
    local bufferImage = {
        WritePixelsBuffer = function(_, position, size, pixels)
            bufferCall = {
                position = position,
                size = size,
                pixels = pixels,
            }
        end,
    }
    EditableImageCompat.WritePixels(bufferImage, Vector2.zero, Vector2.new(2, 1), sample)
    Assert.truthy(
        bufferCall,
        "expected compatibility helper to prefer WritePixelsBuffer when available"
    )
    Assert.equal(
        bufferCall.position,
        Vector2.zero,
        "expected WritePixelsBuffer position passthrough"
    )
    Assert.equal(bufferCall.size, Vector2.new(2, 1), "expected WritePixelsBuffer size passthrough")
    Assert.equal(bufferCall.pixels, sample, "expected WritePixelsBuffer buffer passthrough")

    local legacyCall = nil
    local legacyImage = {
        WritePixels = function(_, position, size, pixels)
            legacyCall = {
                position = position,
                size = size,
                pixels = pixels,
            }
        end,
    }
    EditableImageCompat.WritePixels(legacyImage, Vector2.new(4, 5), Vector2.new(2, 1), sample)
    Assert.truthy(
        legacyCall,
        "expected compatibility helper to fall back to WritePixels on older APIs"
    )
    Assert.equal(legacyCall.position, Vector2.new(4, 5), "expected legacy position passthrough")
    Assert.equal(legacyCall.size, Vector2.new(2, 1), "expected legacy size passthrough")
    Assert.equal(#legacyCall.pixels, 8, "expected buffer fallback to expand to RGBA byte array")
    Assert.equal(legacyCall.pixels[1], 10, "expected legacy fallback first byte")
    Assert.equal(legacyCall.pixels[8], 80, "expected legacy fallback last byte")
end
