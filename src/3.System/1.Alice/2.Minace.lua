---@diagnostic disable: missing-fields, inject-field
if Debug then Debug.beginFile "MINACE" end
---@diagnostic disable: need-check-nil
do
    --[[
    =============================================================================================================================================================
                                                                        Minimal ALICE
                                                                         by Antares
                                                                           v2.6.3

							            A stripped-down version of ALICE, only able to execute its callback API functions.
						
								Requires:
								TotalInitialization			    https://www.hiveworkshop.com/threads/total-initialization.317099/


                                                            For tutorials & documentation, see here:
                                                          https://www.hiveworkshop.com/threads/.353126/

    =============================================================================================================================================================
																	    C O N F I G
    =============================================================================================================================================================
    ]]

    ALICE_Config = {

        --Minimum interval between interactions in seconds. Sets the time step of the timer. All interaction intervals are an integer multiple of this value.
        MIN_INTERVAL = 0.02 ---@constant number

        --Maximum interval between interactions in seconds.
        ,
        MAX_INTERVAL = 10.0 ---@constant number
    }

    --[[
    =============================================================================================================================================================
														            E N D   O F   C O N F I G
    =============================================================================================================================================================
    ]]

    --#region Variables
    ALICE_TimeElapsed                                               = 0.0 ---@type number

    local pack                                                      = table.pack
    local unpack                                                    = table.unpack
    local config                                                    = ALICE_Config

    local MASTER_TIMER ---@type timer
    local MAX_STEPS                                                 = 0 ---@type integer
    local CYCLE_LENGTH                                              = 0 ---@type integer
    local DO_NOT_EVALUATE                                           = 0 ---@type integer

    --Array indices for pair fields. Storing as a sequence up to 8 reduces memory usage.
    local ACTOR_A                                                   = 1 ---@type integer
    local HOST_A                                                    = 3 ---@type integer
    local CURRENT_POSITION                                          = 5 ---@type integer
    local POSITION_IN_STEP                                          = 6 ---@type integer
    local NEXT                                                      = 5 ---@type integer
    local PREVIOUS                                                  = 6 ---@type integer
    local EVERY_STEP                                                = 7 ---@type integer
    local INTERACTION_FUNC                                          = 8 ---@type integer
    local DESTRUCTION_QUEUED                                        = "DQ" ---@type string
    local USER_DATA                                                 = "UD" ---@type string
    local COOLDOWN                                                  = "CD" ---@type string

    local DUMMY_PAIR ---@constant Pair
                                                                    = { [DESTRUCTION_QUEUED] = true }

    local actorOf                                                   = {} ---@type Actor[]

    local cycle                                                     = {
        counter = 0, ---@type integer
        unboundCounter = 0, ---@type integer
        isHalted = false, ---@type boolean
        isCrash = false, ---@type boolean
        freezeCounter = 0, ---@type number
    }

    local currentPair ---@type Pair | nil
    local numPairs                                                  = {} ---@type integer[]
    local whichPairs                                                = {} ---@type table[]
    local firstEveryStepPair                                        = DUMMY_PAIR ---@type Pair
    local lastEveryStepPair                                         = DUMMY_PAIR ---@type Pair
    local numEveryStepPairs                                         = 0 ---@type integer
    local unusedPairs                                               = {} ---@type Pair[]
    local unusedActors                                              = {} ---@type Actor[]
    local unusedTables                                              = {} ---@type table[]
    local functionDelay                                             = {} ---@type table<function,number>
    local delayedCallbackFunctions                                  = {} ---@type function[]
    local delayedCallbackArgs                                       = {} ---@type table[]
    local userCallbacks                                             = {} ---@type table[]

    local INV_MIN_INTERVAL ---@constant number
                                                                    = 1 / config.MIN_INTERVAL - 0.001
    --#endregion

    --===========================================================================================================================================================
    --Utility
    --===========================================================================================================================================================

    --#region Utility
    local function GetTable()
        local numUnusedTables = #unusedTables
        if numUnusedTables == 0 then
            return {}
        else
            local returnTable = unusedTables[numUnusedTables]
            unusedTables[numUnusedTables] = nil
            return returnTable
        end
    end

    local function ReturnTable(whichTable)
        for key, __ in pairs(whichTable) do
            whichTable[key] = nil
        end
        unusedTables[#unusedTables + 1] = whichTable
        setmetatable(whichTable, nil)
    end

    local function AddDelayedCallback(func, arg1, arg2, arg3)
        local index = #delayedCallbackFunctions + 1
        delayedCallbackFunctions[index] = func
        local args = delayedCallbackArgs[index] or {}
        args[1], args[2], args[3] = arg1, arg2, arg3
        delayedCallbackArgs[index] = args
    end

    local function RemoveUserCallbackFromList(self)
        if self == userCallbacks.first then
            if self.next then
                self.next.previous = nil
            else
                userCallbacks.last = nil
            end
            userCallbacks.first = self.next
        elseif self == userCallbacks.last then
            userCallbacks.last = self.previous
            self.previous.next = nil
        else
            self.previous.next = self.next
            self.next.previous = self.previous
        end
    end

    local function ExecuteUserCallback(self)
        if self.args then
            if self.unpack then
                self.callback(unpack(self.args))
                ReturnTable(self.args)
            else
                self.callback(self.args)
            end
        else
            self.callback()
        end

        RemoveUserCallbackFromList(self)
        ReturnTable(self)
    end

    local function AddUserCallback(self)
        if userCallbacks.first == nil then
            userCallbacks.first = self
            userCallbacks.last = self
        else
            local node = userCallbacks.last
            local callCounter = self.callCounter
            while node and node.callCounter > callCounter do
                node = node.previous
            end
            if node == nil then
                --Insert at the beginning
                userCallbacks.first.previous = self
                self.next = userCallbacks.first
                userCallbacks.first = self
            else
                if node == userCallbacks.last then
                    --Insert at the end
                    userCallbacks.last = self
                else
                    --Insert in the middle
                    self.next = node.next
                    self.next.previous = self
                end
                self.previous = node
                node.next = self
            end
        end
    end

    local function PeriodicWrapper(caller)
        if caller.excess > 0 then
            local returnValue = caller.excess
            caller.excess = caller.excess - ALICE_Config.MAX_INTERVAL
            return returnValue
        end
        local returnValue = caller.callback(unpack(caller))
        if returnValue and returnValue > ALICE_Config.MAX_INTERVAL then
            caller.excess = returnValue - ALICE_Config.MAX_INTERVAL
        end
        return returnValue
    end

    local function RepeatedWrapper(caller)
        if caller.excess > 0 then
            local returnValue = caller.excess
            caller.excess = caller.excess - ALICE_Config.MAX_INTERVAL
            return returnValue
        end
        caller.currentExecution = caller.currentExecution + 1
        if caller.currentExecution == caller.howOften then
            ALICE_DisableCallback()
        end
        local returnValue = caller.callback(caller.currentExecution, unpack(caller))
        if returnValue and returnValue > ALICE_Config.MAX_INTERVAL then
            caller.excess = returnValue - ALICE_Config.MAX_INTERVAL
        end
        return returnValue
    end
    --#endregion

    --===========================================================================================================================================================
    --Pair Class
    --===========================================================================================================================================================

    --#region Pair
    ---@class Pair
    local Pair = {
        [ACTOR_A] = nil, ---@type Actor
        [INTERACTION_FUNC] = nil, ---@type function
        [CURRENT_POSITION] = nil, ---@type integer
        [POSITION_IN_STEP] = nil, ---@type integer
        [DESTRUCTION_QUEUED] = nil, ---@type boolean
        [HOST_A] = nil, ---@type any
        [EVERY_STEP] = nil, ---@type boolean
        [COOLDOWN] = nil, ---@type table
    }

    ---@param whichPair Pair
    local function AddPairToEveryStepList(whichPair)
        whichPair[PREVIOUS] = lastEveryStepPair
        whichPair[NEXT] = nil
        lastEveryStepPair[NEXT] = whichPair
        lastEveryStepPair = whichPair
        numEveryStepPairs = numEveryStepPairs + 1
    end

    ---@param whichPair Pair
    local function RemovePairFromEveryStepList(whichPair)
        if whichPair[PREVIOUS] == nil then
            return
        end
        if whichPair[NEXT] then
            whichPair[NEXT][PREVIOUS] = whichPair[PREVIOUS]
        else
            lastEveryStepPair = whichPair[PREVIOUS]
        end

        whichPair[PREVIOUS][NEXT] = whichPair[NEXT]
        whichPair[PREVIOUS] = nil
        numEveryStepPairs = numEveryStepPairs - 1
    end

    ---@param actorA Actor
    ---@param interactionFunc function
    ---@return Pair | nil
    local function CreatePair(actorA, interactionFunc)
        local self ---@type Pair
        if #unusedPairs == 0 then
            self = {}
        else
            self = unusedPairs[#unusedPairs]
            unusedPairs[#unusedPairs] = nil
        end

        self[ACTOR_A] = actorA
        self[HOST_A] = actorA.host

        self[INTERACTION_FUNC] = interactionFunc

        self[DESTRUCTION_QUEUED] = nil

        local firstStep
        if functionDelay[interactionFunc] then
            firstStep = cycle.counter + (functionDelay[interactionFunc] * INV_MIN_INTERVAL + 1) // 1
        else
            firstStep = cycle.counter + 1
        end
        if firstStep > CYCLE_LENGTH then
            firstStep = firstStep - CYCLE_LENGTH
        end
        numPairs[firstStep] = numPairs[firstStep] + 1
        whichPairs[firstStep][numPairs[firstStep]] = self
        self[CURRENT_POSITION] = firstStep
        self[POSITION_IN_STEP] = numPairs[firstStep]

        return self
    end

    local function DestroyPair(self)
        if self[EVERY_STEP] then
            RemovePairFromEveryStepList(self)
        else
            whichPairs[self[CURRENT_POSITION]][self[POSITION_IN_STEP]] = DUMMY_PAIR
        end
        self[CURRENT_POSITION] = nil
        self[POSITION_IN_STEP] = nil
        self[DESTRUCTION_QUEUED] = true

        if self[USER_DATA] then
            ReturnTable(self[USER_DATA])
        end

        unusedPairs[#unusedPairs + 1] = self

        if self[COOLDOWN] then
            ReturnTable(self[COOLDOWN])
            self[COOLDOWN] = nil
        end

        self[EVERY_STEP] = nil
    end

    local function PausePair(self)
        if self[DESTRUCTION_QUEUED] then
            return
        end
        if self[EVERY_STEP] then
            RemovePairFromEveryStepList(self)
        else
            if self[CURRENT_POSITION] ~= DO_NOT_EVALUATE then
                whichPairs[self[CURRENT_POSITION]][self[POSITION_IN_STEP]] = DUMMY_PAIR
                local nextStep = DO_NOT_EVALUATE
                numPairs[nextStep] = numPairs[nextStep] + 1
                whichPairs[nextStep][numPairs[nextStep]] = self
                self[CURRENT_POSITION] = nextStep
                self[POSITION_IN_STEP] = numPairs[nextStep]
            end
        end
    end

    local function UnpausePair(self)
        if self[DESTRUCTION_QUEUED] then
            return
        end
        if self[EVERY_STEP] then
            if self[PREVIOUS] then
                AddPairToEveryStepList(self)
            end
        else
            if self[CURRENT_POSITION] == DO_NOT_EVALUATE then
                local nextStep = cycle.counter + 1
                if nextStep > CYCLE_LENGTH then
                    nextStep = nextStep - CYCLE_LENGTH
                end

                numPairs[nextStep] = numPairs[nextStep] + 1
                whichPairs[nextStep][numPairs[nextStep]] = self
                self[CURRENT_POSITION] = nextStep
                self[POSITION_IN_STEP] = numPairs[nextStep]
            end
        end
    end
    --#endregion

    --===========================================================================================================================================================
    --Actor Class
    --===========================================================================================================================================================

    --#region Actor
    local function GetUnusedActor()
        local self
        if #unusedActors == 0 then
            self = {} ---@type Actor
        else
            self = unusedActors[#unusedActors]
            unusedActors[#unusedActors] = nil
        end
        return self
    end

    ---@class Actor
    local Actor = {
        host = nil, ---@type any
        alreadyDestroyed = nil, ---@type boolean
        periodicPair = nil, ---@type Pair
    }

    CreateStub = function(host, identifier)
        local actor = GetUnusedActor()
        actor.host = host
        actor.alreadyDestroyed = nil
        actorOf[host] = actor
        return actor
    end

    DestroyStub = function(self)
        if self == nil or self.alreadyDestroyed then
            return
        end
        self.periodicPair = nil
        actorOf[self.host] = nil
        self.host = nil
        self.alreadyDestroyed = true
        unusedActors[#unusedActors + 1] = self
    end
    --#endregion

    --===========================================================================================================================================================
    --Main
    --===========================================================================================================================================================

    --#region Main
    local function Main()
        --First-in first-out.
        local k = 1
        while delayedCallbackFunctions[k] do
            delayedCallbackFunctions[k](unpack(delayedCallbackArgs[k]))
            k = k + 1
        end
        for i = 1, #delayedCallbackFunctions do
            delayedCallbackFunctions[i] = nil
        end

        cycle.counter = cycle.counter + 1
        if cycle.counter > CYCLE_LENGTH then
            cycle.counter = 1
        end
        local currentCounter = cycle.counter
        cycle.unboundCounter = cycle.unboundCounter + 1
        ALICE_TimeElapsed = cycle.unboundCounter * config.MIN_INTERVAL

        while userCallbacks.first and userCallbacks.first.callCounter == cycle.unboundCounter do
            ExecuteUserCallback(userCallbacks.first)
        end

        local numSteps, nextStep

        --Every Step Cycle
        currentPair = firstEveryStepPair
        for __ = 1, numEveryStepPairs do
            currentPair = currentPair[NEXT]
            if not currentPair[DESTRUCTION_QUEUED] then
                currentPair[INTERACTION_FUNC](currentPair[HOST_A])
            end
        end

        --Variable Step Cycle
        local returnValue
        local pairsThisStep = whichPairs[currentCounter]
        for i = 1, numPairs[currentCounter] do
            currentPair = pairsThisStep[i]
            if currentPair[DESTRUCTION_QUEUED] then
                if currentPair ~= DUMMY_PAIR then
                    nextStep = currentCounter + MAX_STEPS
                    if nextStep > CYCLE_LENGTH then
                        nextStep = nextStep - CYCLE_LENGTH
                    end

                    numPairs[nextStep] = numPairs[nextStep] + 1
                    whichPairs[nextStep][numPairs[nextStep]] = currentPair
                    currentPair[CURRENT_POSITION] = nextStep
                    currentPair[POSITION_IN_STEP] = numPairs[nextStep]
                end
            else
                returnValue = currentPair[INTERACTION_FUNC](currentPair[HOST_A])
                if returnValue then
                    numSteps = (returnValue * INV_MIN_INTERVAL + 1) // 1 --convert seconds to steps, then ceil.
                    if numSteps < 1 then
                        numSteps = 1
                    elseif numSteps > MAX_STEPS then
                        numSteps = MAX_STEPS
                    end

                    nextStep = currentCounter + numSteps
                    if nextStep > CYCLE_LENGTH then
                        nextStep = nextStep - CYCLE_LENGTH
                    end

                    numPairs[nextStep] = numPairs[nextStep] + 1
                    whichPairs[nextStep][numPairs[nextStep]] = currentPair
                    currentPair[CURRENT_POSITION] = nextStep
                    currentPair[POSITION_IN_STEP] = numPairs[nextStep]
                else
                    AddPairToEveryStepList(currentPair)
                    currentPair[EVERY_STEP] = true
                end
            end
        end

        numPairs[currentCounter] = 0

        currentPair = nil

        k = 1
        while delayedCallbackFunctions[k] do
            delayedCallbackFunctions[k](unpack(delayedCallbackArgs[k]))
            k = k + 1
        end
        for i = 1, #delayedCallbackFunctions do
            delayedCallbackFunctions[i] = nil
        end
    end
    --#endregion

    --===========================================================================================================================================================
    --Init
    --===========================================================================================================================================================

    --#region Init
    local function Init()
        MASTER_TIMER = CreateTimer()
        MAX_STEPS = (config.MAX_INTERVAL / config.MIN_INTERVAL) // 1
        CYCLE_LENGTH = MAX_STEPS + 1
        DO_NOT_EVALUATE = CYCLE_LENGTH + 1

        for i = 1, DO_NOT_EVALUATE do
            numPairs[i] = 0
            whichPairs[i] = {}
        end

        TimerStart(MASTER_TIMER, config.MIN_INTERVAL, true, Main)
    end

    OnInit.final("ALICE", Init)
    --#endregion

    --===========================================================================================================================================================
    --API
    --===========================================================================================================================================================

    ---Returns a table unique to the pair currently being evaluated, which can be used to read and write data. Optional argument to set a metatable for the data table.
    ---@param whichMetatable? table
    ---@return table
    function ALICE_PairLoadData(whichMetatable)
        if currentPair == nil then
            error("Attempted to call Pair API function from outside of allowed functions.")
        end

        if currentPair[USER_DATA] == nil then
            currentPair[USER_DATA] = GetTable()
            setmetatable(currentPair[USER_DATA], whichMetatable)
        end
        return currentPair[USER_DATA]
    end

    ---Returns the remaining cooldown for this pair, then invokes a cooldown of the specified duration. Optional cooldownType parameter to create and differentiate between multiple separate cooldowns.
    ---@param duration number
    ---@param cooldownType? string
    ---@return number
    function ALICE_PairCooldown(duration, cooldownType)
        if currentPair == nil then
            error("Attempted to call Pair API function from outside of allowed functions.")
        end

        currentPair[COOLDOWN] = currentPair[COOLDOWN] or GetTable()
        local key = cooldownType or "default"
        local cooldownExpiresStep = currentPair[COOLDOWN][key]

        if cooldownExpiresStep == nil or cooldownExpiresStep <= cycle.unboundCounter then
            currentPair[COOLDOWN][key] = cycle.unboundCounter + (duration * INV_MIN_INTERVAL + 1) // 1
            return 0
        else
            return (cooldownExpiresStep - cycle.unboundCounter) * config.MIN_INTERVAL
        end
    end

    ---Modifies the return value of an interactionFunc so that, on average, the interval is the specified value, even if it isn't an integer multiple of the minimum interval.
    ---@param value number
    ---@return number
    function ALICE_PairPreciseInterval(value)
        if currentPair == nil then
            error("Attempted to call Pair API function from outside of allowed functions.")
        end

        local ALICE_MIN_INTERVAL = config.MIN_INTERVAL

        local data = ALICE_PairLoadData()
        local numSteps = (value * INV_MIN_INTERVAL + 1) // 1
        local newDelta = (data.returnDelta or 0) + value - ALICE_MIN_INTERVAL * numSteps
        if newDelta > 0.5 * ALICE_MIN_INTERVAL then
            newDelta = newDelta - ALICE_MIN_INTERVAL
            numSteps = numSteps + 1
            data.returnDelta = newDelta
        elseif newDelta < -0.5 * ALICE_MIN_INTERVAL then
            newDelta = newDelta + ALICE_MIN_INTERVAL
            numSteps = numSteps - 1
            data.returnDelta = newDelta
            if numSteps == 0 and not currentPair[DESTRUCTION_QUEUED] then
                currentPair[INTERACTION_FUNC](currentPair[HOST_A])
            end
        else
            data.returnDelta = newDelta
        end
        return ALICE_MIN_INTERVAL * numSteps
    end

    ---Invokes the callback function after the specified delay, passing additional arguments into the callback function.
    ---@param callback function
    ---@param delay? number
    ---@vararg any
    function ALICE_CallDelayed(callback, delay, ...)
        local new = GetTable()
        new.callCounter = cycle.unboundCounter + ((delay or 0) * INV_MIN_INTERVAL + 1) // 1
        new.callback = callback
        local numArgs = select("#", ...)
        if numArgs == 1 then
            new.args = select(1, ...)
        elseif numArgs > 1 then
            new.args = pack(...)
            new.unpack = true
        end

        AddUserCallback(new)

        return new
    end

    ---Periodically invokes the callback function. Optional delay parameter to delay the first execution. Additional arguments are passed into the callback function. The return value of the callback function specifies the interval until next execution.
    ---@param callback function
    ---@param delay? number
    ---@vararg any
    ---@return table
    function ALICE_CallPeriodic(callback, delay, ...)
        local host = pack(...)
        host.callback = callback
        host.excess = delay or 0
        host.isPeriodic = true
        local actor = CreateStub(host)
        actor.periodicPair = CreatePair(actor, PeriodicWrapper)

        return host
    end

    ---Periodically invokes the callback function up to howOften times. Optional delay parameter to delay the first execution. The arguments passed into the callback function are the current iteration, followed by any additional arguments. The return value of the callback function specifies the interval until next execution.
    ---@param callback function
    ---@param howOften integer
    ---@param delay? number
    ---@vararg any
    ---@return table
    function ALICE_CallRepeated(callback, howOften, delay, ...)
        local host = pack(...)
        host.callback = callback
        host.howOften = howOften
        host.currentExecution = 0
        host.excess = delay or 0
        host.isPeriodic = true
        local actor = CreateStub(host)
        if howOften > 0 then
            actor.periodicPair = CreatePair(actor, RepeatedWrapper)
        end

        return host
    end

    ---Disables a callback returned by ALICE_CallDelayed, ALICE_CallPeriodic, or ALICE_CallRepeated. If called from within a periodic callback function itself, the parameter can be omitted.
    ---@param callback? table
    function ALICE_DisableCallback(callback)
        local actor
        if callback then
            if callback.isPeriodic then
                actor = actorOf[callback]
                if actor == nil or actor.alreadyDestroyed then
                    return
                end

                AddDelayedCallback(DestroyPair, actor.periodicPair)
                DestroyStub(actor)
            else
                if callback.callCounter == nil or callback.callCounter <= cycle.unboundCounter then
                    return
                end
                if not callback.isPaused then
                    RemoveUserCallbackFromList(callback)
                end
                ReturnTable(callback)
                return
            end
        elseif currentPair ~= nil then
            actor = currentPair[ACTOR_A]
            if actor == nil or actor.alreadyDestroyed then
                return
            end

            AddDelayedCallback(DestroyPair, actor.periodicPair)
            DestroyStub(actor)
        end
    end

    local remindedOfDisablePeriodic
    ---Deprecated. Use ALICE_DisableCallback instead
    ---@deprecated
    function ALICE_DisablePeriodic(callback)
        if not remindedOfDisablePeriodic then
            remindedOfDisablePeriodic = true
            print("|cffff0000Warning:|r ALICE_DisablePeriodic is deprecated. Use ALICE_DisableCallback instead.")
        end
        ALICE_DisableCallback(callback)
    end

    ---Pauses or unpauses a callback returned by ALICE_CallDelayed, ALICE_CallPeriodic, or ALICE_CallRepeated. If a periodic callback is unpaused this way, the next iteration will be executed immediately. Otherwise, the remaining time will be waited. If called from within a periodic callback function itself, the callback parameter can be omitted.
    ---@param callback? table
    ---@param enable? boolean
    function ALICE_PauseCallback(callback, enable)
        enable = enable ~= false

        local actor
        if callback then
            if callback.isPeriodic then
                if callback.isPaused == enable then
                    return
                end
                callback.isPaused = enable

                actor = actorOf[callback]
                if enable then
                    PausePair(actor.periodicPair)
                else
                    UnpausePair(actor.periodicPair)
                end
            else
                if callback.callCounter == nil then
                    return
                end

                if callback.isPaused == enable then
                    return
                end
                callback.isPaused = enable

                if enable then
                    if callback.callCounter <= cycle.unboundCounter then
                        return
                    end
                    callback.stepsRemaining = callback.callCounter - cycle.unboundCounter
                    RemoveUserCallbackFromList(callback)
                else
                    callback.callCounter = cycle.unboundCounter + callback.stepsRemaining
                    AddUserCallback(callback)
                end
                return
            end
        elseif currentPair ~= nil then
            if callback.isPaused == enable then
                return
            end
            callback.isPaused = enable

            actor = currentPair[ACTOR_A]
            if enable then
                PausePair(actor.periodicPair)
            else
                UnpausePair(actor.periodicPair)
            end
        else

        end
    end
end
