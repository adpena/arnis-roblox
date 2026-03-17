local Assert = {}

function Assert.equal(actual, expected, message)
    if actual ~= expected then
        error(message or ("expected %s but got %s"):format(tostring(expected), tostring(actual)), 2)
    end
end

function Assert.truthy(value, message)
    if not value then
        error(message or "expected truthy value", 2)
    end
end

function Assert.falsy(value, message)
	if value then
		error(message or "expected falsy value", 2)
	end
end

function Assert.near(actual, expected, epsilon, message)
    epsilon = epsilon or 1e-6
    if math.abs(actual - expected) > epsilon then
        error(message or ("expected %s to be within %s of %s"):format(actual, epsilon, expected), 2)
    end
end

return Assert
