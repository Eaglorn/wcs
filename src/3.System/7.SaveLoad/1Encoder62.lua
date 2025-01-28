if Debug then Debug.beginFile "Encoder62" end
OnInit.root("Encoder62", function()
    -- Alphanumeric character set for Base62
    local base62Chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    local fmod = math.fmod
    Base62 = {}
    ---Convert a number to a Base62 string
    ---@param num number
    ---@return string
    function Base62.toBase62(num)
        local base = 62
        local result = ""

        local isNegative = false
        if num < 0 then
            num = -num
            isNegative = true
        end
        repeat
            -- Get the remainder when dividing the number by Base62
            local remainder = fmod(num, base)
            -- Map the remainder to the corresponding Base62 character
            result = base62Chars:sub(remainder + 1, remainder + 1) .. result
            -- Update the number (integer division by base)
            num = math.tointeger(num // base)
        until num == 0
        return isNegative and "-" .. result or result
    end

    ---Convert a Base62 string back to a number
    ---@param base62Str string
    ---@return number
    function Base62.fromBase62(base62Str)
        local base = 62
        local num = 0
        local isNegative = false
        if base62Str:sub(1, 1) == "-" then
            isNegative = true
            base62Str = base62Str:sub(2, base62Str:len())
        end
        for i = 1, #base62Str do
            -- Get the value of the current character in Base62
            local char = base62Str:sub(i, i)
            local value = base62Chars:find(char) - 1 -- find returns 1-based index
            -- Accumulate the value into the result
            num = num * base + value
        end
        return isNegative and -num or num
    end
end)
if Debug then Debug.endFile() end
