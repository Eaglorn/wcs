---@diagnostic disable: redundant-return-value
if Debug then Debug.beginFile "SaveLoadHelper" end
OnInit.module("SaveLoadHelper", function(require)
    require "Encoder62"
    require "FileIO"
--[[
    SaveLoadHelper version 1.3 by Wrda
    (Special thanks to Antares)
    This system is responsible in squeezing a player's data from a table and then retrieving it matching
    how it was saved in. For example, you save a player's data such as PlayerSave (table) which has the fields
    set to some value you set:
    kills; gems; lives; locationX; locationY
    Loading the file will result in a new table, with those exact same fields, and their respective values.
    There are different methods to save data, a table with string keys, as described above, and a table with
    indexed keys. Both have their strengths.
    WARNING: You can't use \x25 (percentage sign) on a string. The loading will fail.
    The workaround for this is to think of a character you'll never going to use and then replace it
    with \x25\x25 (double because it escapes the sign).
    Example: str = "takes 5< damage, 600< more hp"
    local result = string.gsub(str, "<", "\x25\x25")
    print(result)      -> "takes 5% damage, 600% more hp"
    API:
        ---@param playerName string
        ---@return string
        function SaveLoad.getDefaultPath(playerName)
            - Gets the default string format path.
        ---@param p player
        ---@param list table
        ---@param playerName string?
        ---@param filePath string?
        SaveLoad.saveHelperDynamic(p, list, playerName?, filePath?)
            - Saves data to a single player. "list" must be a string-key table.
            - If not given a playerName, it is saved with the current player name.
            - Returns the resulting table in key-indexed format.
        ---@param p player
        ---@param list table<integer, any>
        ---@param playerName string?
        ---@param filePath string?
        SaveLoad.saveHelperIndex(p, list, playerName?, filePath?)
            - Saves data to a single player. "list" must be an indexed-key table.
            - If not given a playerName, it is saved with the current player name.
            - Returns the "list" table, may be useful in when one uses SaveLoad.saveHelperDynamic because it
              calls SaveLoad.saveHelperIndex inside.
        ---@param data string
        ---@return table
        SaveLoad.loadHelperIndex(data)
            return loadDataIndex(data)
            - Loads data into a table. The table will have indexed keys.
        ---@param data string
        ---@return table<string, any>
        function SaveLoad.loadHelperDynamic(data)
            - Loads data into a table. The table will have string keys.     
    ]]
    SaveLoad = {}
--[[----------------------------------------------------------------------------------------------------
                            CONFIGURATION                                                             ]]
    SaveLoad.FOLDER = "TEST MAP"         -- Name of the folder. Not required, but serves as a default.
    SaveLoad.FILE_PREFIX = "TestCode-"  -- You can have none. Use empty string and NOT nil. Not required, but serves as a default.
    SaveLoad.FILE_SUFFIX = "-0"         -- You can have none. Use empty string and NOT nil. Not required, but serves as a default.
    SAVE_LOAD_SEED = 1                  -- This is used for generating a random permutation of the scrambled string. Set it to any integer unique for your map. You're not supposed to change your mind on this later on.
 
    ---Gets the default string format path.
    ---@param playerName string
    ---@return string
    function SaveLoad.getDefaultPath(playerName)
        return SaveLoad.FOLDER .. "\\" .. SaveLoad.FILE_PREFIX .. playerName .. SaveLoad.FILE_SUFFIX .. ".pld"
    end
    --------------------------------------------------------------------------------------------------------
    local pack = string.pack
    local unpack = string.unpack
    local byte = string.byte
    local pseudoRandomPermutation
    local delimiterList = {
        ["integer"] = "#",
        ["float"] = "_",
        ["string"] = "&",
        ["true"] = "!",
        ["false"] = "@",
        --reverse
        ["#"] = "integer",
        ["_"] = "float",
        ["&"] = "string",
        ["!"] = "true",
        ["@"] = "false"
    }
    ---@param value any
    local function getDelimiterType(value)
        local mathType = math.type(value)
        if delimiterList[mathType] then
            return delimiterList[mathType]
        elseif type(value) == "string" then
            return delimiterList[type(value)]
        elseif type(value) == "boolean" then
            return delimiterList[tostring(value)]
        else
            error("Unrecognized delimiter type.")
        end
        return nil
    end
    ---@param str string
    ---@param pos integer
    ---@return string|nil
    local function findDelimiterTypeIndex(str, pos)
        local found
        found = str:match("([#_&!@])\x25d+", pos)
        return found
    end
    ---@param str string
    ---@param pos integer
    ---@return string|nil
    local function findDelimiterTypeDynamic(str, pos)
        local found
        found = str:match("([#_&!@])\x25w+", pos)
        return found
    end
    --compress
    ---@param float number
    ---@return integer
    local function binaryFloat2Integer(float)
        return unpack("i4", pack("f", float))
    end
    ---@param integer integer
    ---@return number
    local function binaryInteger2Float(integer)
        return string.unpack("f", string.pack("i4", integer))
    end
    --validating parts of the file
    ---@param str string
    ---@return integer
    local function getCheckNumber(str)
        local checkNum = 0
        for i = 1, str:len() do
            checkNum = checkNum + byte(str:sub(i, i))
        end
        return checkNum
    end
    ---@param str string
    ---@return string
    local function addCheckNumber(str)
        return Base62.toBase62(getCheckNumber(str)) .. "-" .. str
    end
    ---@param str string
    ---@return string, boolean
    local function separateAndValidateCheckNumber(str)
        local separatedString = str:sub(str:find("-") + 1, str:len())
        return separatedString, getCheckNumber(separatedString) == Base62.fromBase62(str:sub(1, str:find("-") - 1))
    end
    ---@param str string
    ---@param seed integer
    ---@return string
    pseudoRandomPermutation = function(str, seed)
        local oldSeed = math.random(0, 2147483647)
        math.randomseed(seed)
 
        local chars = {}
        for i = 1, #str do
            table.insert(chars, str:sub(i, i))
        end
 
        for i = #chars, 2, -1 do
            local j = math.random(i)
            chars[i], chars[j] = chars[j], chars[i]
        end
 
        math.randomseed(oldSeed)
 
        return table.concat(chars)
    end
    --scrambler
    local chars = [[!#$&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ^_`abcdefghijklmnopqrstuvwxyz{|}~]]
    local scrambled = pseudoRandomPermutation(chars, SAVE_LOAD_SEED)
    local SCRAMBLED = {}
    local UNSCRAMBLED = {}
    for i = 1, chars:len() do
        SCRAMBLED[chars:sub(i, i)] = scrambled:sub(i, i)
        UNSCRAMBLED[scrambled:sub(i, i)] = chars:sub(i, i)
    end
    local function scrambleString(whichString)
        local scrambledString = ""
        for i = 1, whichString:len() do
            scrambledString = scrambledString .. (SCRAMBLED[whichString:sub(i, i)] or whichString:sub(i, i))
        end
        return scrambledString
    end
    local function unscrambleString(whichString)
        local unscrambledString = ""
        for i = 1, whichString:len() do
            unscrambledString = unscrambledString .. (UNSCRAMBLED[whichString:sub(i, i)] or whichString:sub(i, i))
        end
        return unscrambledString
    end
    local function convertToIndexedTable(dynamicTable)
        --you may use a table recycler here
        local indexedTable = {}
        for key, value in pairs(dynamicTable) do
            indexedTable[#indexedTable + 1] = key
            indexedTable[#indexedTable + 1] = value
        end
        return indexedTable
    end
    local function convertToDictionary(indexedTable)
        --you may use a table recycler here
        local dynamicTable = {}
        for i = 1, #indexedTable, 2 do
            dynamicTable[indexedTable[i]] = indexedTable[i + 1]
        end
        return dynamicTable
    end
    ---Saves data to a single player. "list" must be a string-key table.
    ---If not given a playerName, it is saved with the current player name.
    ---Returns the resulting table in key-indexed format.
    ---@param p player
    ---@param list table
    ---@param playerName string?
    ---@param filePath string?
    ---@return table
    function SaveLoad.saveHelperDynamic(p, list, playerName, filePath)
        local indexedTable = convertToIndexedTable(list)
        return SaveLoad.saveHelperIndex(p, indexedTable, playerName, filePath)
    end
    ---Saves data to a single player. "list" must be an indexed-key table.
    ---If not given a playerName, it is saved with the current player name.
    ---Returns the "list" table, may be useful in when one uses SaveLoad.saveHelperDynamic because it calls SaveLoad.saveHelperIndex inside.
    ---@param p player
    ---@param list table<integer, any>
    ---@param playerName string?
    ---@param filePath string?
    ---@return table
    function SaveLoad.saveHelperIndex(p, list, playerName, filePath)
        local data = ""
        local delimiterType
        local value
        for _, v in ipairs(list) do
            delimiterType = getDelimiterType(v)
            if delimiterList[delimiterType] == "float" then
                value = binaryFloat2Integer(v)
                value = Base62.toBase62(value)
            elseif delimiterList[delimiterType] == "integer" then
                value = Base62.toBase62(v)
            else
                value = tostring(v)
            end
            if type(v) == "boolean" then
                data = data .. delimiterType .. Base62.toBase62(0) .. delimiterType
            else
                data = data .. delimiterType .. Base62.toBase62(string.len(value)) .. delimiterType .. value
            end
        end
        data = addCheckNumber(data)
        local encData = scrambleString(data)
        if not playerName then
            playerName = GetPlayerName(p)
        end
        local path = type(filePath) == "string" and filePath or SaveLoad.getDefaultPath(playerName)
        if GetLocalPlayer() == p then
            FileIO.Save(path, encData)
        end
        return list
    end
 
    ---Loads data into a table. The table will have indexed keys.
    ---@param scrambledData string
    ---@return table<integer, any>|nil
    function SaveLoad.loadHelperIndex(scrambledData)
        local unscrambled = unscrambleString(scrambledData)
        local oldpos = 1
        local i = 1
        local data, isValid = separateAndValidateCheckNumber(unscrambled)
        if not isValid then
            --tampering detected
            return nil
        end
        local max = data:len()
        --you may use a table recycler here
        output = {}
        repeat
            local delType = findDelimiterTypeIndex(data, oldpos)
            local _, fin, length = data:find(delType .. "(\x25w+)" .. delType, oldpos) --\x25w+ because base62
            length = Base62.fromBase62(length)
            oldpos = fin + length + 1
            local value
            if length == 0 then     --boolean data always has 0 length
                value = (delimiterList[delType] == "true") and true or false
                goto skip
            else
                value = string.sub(data, fin + 1, length + fin)
            end
            if delimiterList[delType] == "float" then
                value = binaryInteger2Float(Base62.fromBase62(value))
            elseif delimiterList[delType] == "integer" then
                value = math.tointeger(Base62.fromBase62(value))
            end
            ::skip::    --skip if delimiter type was a boolean
            output[i] = value
            i = i + 1
        until oldpos >= max
        return output
    end
    ---Loads scrambledData into a table. The table will have string keys.
    ---@param scrambledData string
    ---@return table<string, any>|nil
    function SaveLoad.loadHelperDynamic(scrambledData)
        local unscrambled = unscrambleString(scrambledData)
        local oldpos = 1
        local i = 1
        local data, isValid = separateAndValidateCheckNumber(unscrambled)
        if not isValid then
            --tampering detected
            return nil
        end
        local max = data:len()
        --you may use a table recycler here
        output = {}
        repeat
            local delType = findDelimiterTypeDynamic(data, oldpos)
            local _, fin, length = data:find(delType .. "(\x25w+)" .. delType, oldpos) --\x25w+ because base62
            length = Base62.fromBase62(length)
            oldpos = fin + length + 1
            local value
            if length == 0 then     --boolean data always has 0 length
                value = (delimiterList[delType] == "true") and true or false
                goto skip
            else
                value = string.sub(data, fin + 1, length + fin)
            end
            if delimiterList[delType] == "float" then
                value = binaryInteger2Float(Base62.fromBase62(value))
            elseif delimiterList[delType] == "integer" then
                value = math.tointeger(Base62.fromBase62(value))
            end
            ::skip::    --skip if delimiter type was a boolean
            output[i] = value
            i = i + 1
        until oldpos >= max
        local dictionaryTable = convertToDictionary(output)
        --recycle the table if you have a table recycler
        output = nil
        return dictionaryTable
    end
end)
if Debug then Debug.endFile() end