local EditableImageCompat = {}

local function bufferToArray(pixels)
    local length = buffer.len(pixels)
    local array = table.create(length)
    for index = 0, length - 1 do
        array[index + 1] = buffer.readu8(pixels, index)
    end
    return array
end

function EditableImageCompat.WritePixels(image, position, size, pixels)
    if image.WritePixelsBuffer then
        image:WritePixelsBuffer(position, size, pixels)
        return
    end

    if image.WritePixels then
        image:WritePixels(position, size, bufferToArray(pixels))
        return
    end

    error("EditableImage does not support WritePixelsBuffer or WritePixels", 2)
end

return EditableImageCompat
