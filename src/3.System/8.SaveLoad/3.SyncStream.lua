if Debug then Debug.beginFile "SyncStream" end
--[[
    By Trokkin
    Provides functionality to designed to safely sync arbitrary amounts of data.
    Uses timers to spread BlzSendSyncData calls over time.
    Wrda's version - not using his encoder
    API:
    ---@param whichPlayer player
    ---@param getLocalData string | fun():string
    ---@param callBackFunctionName string
    function SyncStream.sync(whichPlayer, getLocalData, callBackFunctionName)
       - Adds getLocalData (string or function that returns string) to the queue to be synced. Once completed, fires the funcName function.
       - your callBackFunctionName function MUST take the synced string and the owner of the string as parameters.
    ]]
OnInit.module("Sync Stream", function()
    --CONFIGURATION
    local PREFIX = "Sync"
    local CHUNK_SIZE = 200             --string length per chunk
    local PACKAGE_PER_TICK = 32        --amount of packages per interval
    local PACKAGE_TICK_PER_SECOND = 32 --interval in which the syncing takes place
    local MAX_IDS = 999
    local MAX_CHUNKS = 99
    local DELIMITER = "!" --function delimiter character
    --END CONFIGURATION
    --internal
    local streams = {}
    ---Returns the function from the given string. Also works with functions within tables, the keys MUST be of string type.
    ---@param funcName string
    ---@return function
    local function getFunction(funcName)
        local f = _G
        for v in funcName:gmatch("[^\x25.]+") do
            f = f[v]
        end
        return type(f) == "function" and f or error("value is not a function")
    end

    ---@param maxNum number
    ---@param currentAmount number
    local function fillBlankDigits(maxNum, currentAmount)
        local digits = #tostring(maxNum) - #tostring(currentAmount)
        local blank = ""
        for i = 1, digits do
            blank = blank .. "0"
        end
        return blank
    end
    ---@class syncQueue
    ---@field id integer
    ---@field idLength integer
    ---@field length integer
    ---@field chunks string[]
    ---@field next_chunk integer
    ---@field callbackName string
    local syncQueue = {}
    syncQueue.__index = syncQueue
    ---@param id integer The id of the promise.
    ---@param data string Data to be sent from the local player.
    function syncQueue.create(id, data)
        local queue = setmetatable({
            id = id,
            chunks = {},
            next_chunk = 0,
            length = #data,
            callbackName = ""
        }, syncQueue)
        for i = 1, #data, CHUNK_SIZE do
            queue.chunks[#queue.chunks + 1] = data:sub(i, i + CHUNK_SIZE - 1)
        end
        if #queue.chunks > MAX_CHUNKS then
            error("WARNING: Max CHUNK digits reached!")
        end
        return queue
    end

    function syncQueue:pop()
        if self.next_chunk > #self.chunks then
            self = nil
            return
        end
        --assign id to chunk
        local idDigit0 = fillBlankDigits(MAX_IDS, self.id)
        local chunkDigit0 = fillBlankDigits(MAX_CHUNKS, self.next_chunk)
        local package = idDigit0 .. tostring(self.id) .. chunkDigit0 .. tostring(self.next_chunk)
        --print("SYNC POP")
        --print(self.id, self.next_chunk)
        if self.next_chunk == 0 then
            local maxChunkDigit0 = fillBlankDigits(MAX_CHUNKS, #self.chunks)
            package = DELIMITER ..
            self.callbackName .. DELIMITER .. package .. maxChunkDigit0 .. #self.chunks .. self.length
            --print("OVERALL PACKAGE LENGTH: " .. self.length)
            --print(package)
        else
            --print("THIS PACKAGE")
            package = package .. self.chunks[self.next_chunk]
        end
        -- print(">", self.next_chunk, package)
        if BlzSendSyncData(PREFIX, package) then
            self.next_chunk = self.next_chunk + 1
        end
    end

    --[ PROMISE CLASS ]--
    ---@class promise
    ---@field id integer
    ---@field length integer?
    ---@field next_chunk integer
    ---@field chunks string[]
    ---@field queue syncQueue?
    local promise = {}
    promise.__index = promise
    ---@param id integer The id of the promise.
    function promise.create(id)
        return setmetatable({
            id = id,
            chunks = {},
            next_chunk = 0,
            length = nil,
            queue = nil,
        }, promise)
    end

    function promise:consume(chunk_id, package)
        --print("prev: " .. self.next_chunk)
        if self.length and self.length <= (self.next_chunk - 1) * CHUNK_SIZE then
            return
        end
        -- print("<", chunk_id, package)
        self.chunks[chunk_id] = package
        while self.next_chunk <= chunk_id and self.chunks[self.next_chunk] ~= nil do
            self.next_chunk = self.next_chunk + 1
        end
        --print("now: " .. self.next_chunk)
        --new DISABLED
        --if self.length and self.length <= (self.next_chunk - 1) * CHUNK_SIZE then
        --    self.callback(table.concat(self.chunks), GetTriggerPlayer())
        --end
    end

    local syncTimer
    --[ SYNC STREAM CLASS ]--
    local syncTrigger ---@type trigger
    local localPlayer
    --- Sends or receives player's data assymentrically
    ---@class SyncStream
    ---@field owner player
    ---@field is_local boolean
    ---@field next_promise integer
    ---@field promises promise[]
    SyncStream = {}
    SyncStream.__index = SyncStream
    ---@param owner player The player owning the data from the stream
    local function CreateSyncStream(owner)
        return setmetatable({
            owner = owner,
            is_local = owner == localPlayer,
            next_promise = 1,
            promises = {}
        }, SyncStream)
    end
    ---Adds getLocalData (string or function that returns string) to the queue to be synced. Once completed, fires the callBackFunctionName function.
    ---your callBackFunctionName function MUST take the synced string and the owner of the string as parameters.
    ---@param whichPlayer player
    ---@param getLocalData string | fun():string
    ---@param callBackFunctionName string
    function SyncStream.sync(whichPlayer, getLocalData, callBackFunctionName)
        if not getLocalData then return end
        local self = streams[GetPlayerId(whichPlayer)] ---@type SyncStream
        if #self.promises == MAX_IDS then
            error("WARNING: Max ID digits reached!")
            return
        end
        local promise = promise.create(#self.promises + 1)
        --print("created promise id:" .. promise.id)
        if self.is_local then
            if type(getLocalData) == "function" then
                getLocalData = getLocalData()
            end
            if type(getLocalData) ~= "string" then
                getLocalData = "sync error: bad data type provided " .. type(getLocalData)
            end
            promise.queue = syncQueue.create(promise.id, getLocalData)
            promise.queue.callbackName = callBackFunctionName
            --print("created queue id:" .. promise.queue.id)
        end
        self.promises[promise.id] = promise
    end

    OnInit.final(function()
        syncTimer = CreateTimer()
        localPlayer = GetLocalPlayer()
        local playerSyncedPromises = {}
        for i = 0, bj_MAX_PLAYER_SLOTS - 1 do
            streams[i] = CreateSyncStream(Player(i)) ---@type SyncStream
            --new
            playerSyncedPromises[Player(i)] = {}
        end
        --- Setup sender timer
        local s = streams[GetPlayerId(GetLocalPlayer())] ---@type SyncStream
        if not s.is_local then
            print("SyncStream panic: local stream is not local")
            return
        end
        TimerStart(syncTimer, 1 / PACKAGE_TICK_PER_SECOND, true, function()
            for i = 1, PACKAGE_PER_TICK do
                while s.next_promise <= #s.promises and s.promises[s.next_promise].queue == nil do
                    s.next_promise = s.next_promise + 1
                end
                if s.promises[s.next_promise] == nil then
                    return
                end
                local q = s.promises[s.next_promise].queue
                if q == nil then
                    return
                end
                --process sync queue
                q:pop()
                if q.next_chunk > #q.chunks then
                    s.promises[s.next_promise].queue = nil
                    s.promises[s.next_promise].queue = s.promises[#s.promises].queue
                    s.promises[#s.promises] = nil
                    s.next_promise = math.max(s.next_promise - 1, 1)
                end
            end
        end)
        --- Setup receiver trigger
        syncTrigger = CreateTrigger()
        for i = 0, bj_MAX_PLAYER_SLOTS - 1 do
            BlzTriggerRegisterPlayerSyncEvent(syncTrigger, Player(i), PREFIX, false)
        end
        TriggerAddAction(syncTrigger, function()
            local owner = GetTriggerPlayer()
            local package = BlzGetTriggerSyncData()
            local stream = streams[GetPlayerId(owner)]
            if stream == nil then
                print("SyncStream panic: no stream found for player" .. GetPlayerName(owner) .. "but got 'nothing'")
                return
            end
            --print("START")
            --print(#package, package)
            local _, startPos, funcName = nil, 0, nil
            --check if string starts with the delimiter, then it's the first time the promise is getting synced
            --and the position will be adjusted.
            --if not, then default position is 1.
            if package:sub(1, 1):match(DELIMITER) then
                _, startPos, funcName = package:find(DELIMITER .. "(\x25a[\x25w_.]*)" .. DELIMITER)
            end
            local id = tonumber(string.sub(package, startPos + 1, startPos + #tostring(MAX_IDS)))
            local promise = stream.promises[id]
            --local chunk_id = promise.queue.id ignore this comment
            local chunk_id = tonumber(string.sub(package, startPos + #tostring(MAX_IDS) + 1,
                startPos + #tostring(MAX_IDS) + #tostring(MAX_CHUNKS)))
            --new
            if chunk_id == 0 then
                local max_chunks = tonumber(string.sub(package, startPos + #tostring(MAX_IDS) + #tostring(MAX_CHUNKS) + 1,
                    startPos + #tostring(MAX_IDS) + #tostring(MAX_CHUNKS) * 2))
                playerSyncedPromises[owner][id] = {}
                playerSyncedPromises[owner][id].maxChunks = max_chunks
                playerSyncedPromises[owner][id].callback = funcName
            else
                playerSyncedPromises[owner][id][chunk_id] = package:sub(#tostring(MAX_IDS) + #tostring(MAX_CHUNKS) + 1)
                if chunk_id == playerSyncedPromises[owner][id].maxChunks then
                    --execute callback, inputs data and player
                    getFunction(playerSyncedPromises[owner][id].callback)(table.concat(playerSyncedPromises[owner][id]),
                        owner)
                    playerSyncedPromises[owner][id] = nil
                    return
                end
            end
            if not promise then
                --async area
                --triggers for player B when player A is getting synced data
                --print("SyncStream panic: no promise found for id", id)
                return
            end
            --print("CHUNK ID: ")
            --print(chunk_id)
            if chunk_id == 0 then
                if not promise.queue then return end
                promise.length = promise.queue.length or 0 --data_length
                promise.next_chunk = 1
                return
            end
            --print("CONSUME")
            --print(package:sub(#tostring(MAX_IDS) + #tostring(MAX_CHUNKS) + 1))
            promise:consume(chunk_id, package:sub(#tostring(MAX_IDS) + #tostring(MAX_CHUNKS) + 1))
        end)
    end)
end)
if Debug then Debug.endFile() end
