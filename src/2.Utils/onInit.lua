---@diagnostic disable: lowercase-global
do
    local funcs = {}

    function OnInit.main(code)
        if type(code) == "function" then
            table.insert(funcs, code)
        end
    end

    local old = InitBlizzard
    function InitBlizzard()
        old()

        for i = 1, #funcs do
            funcs[i]()
        end

        funcs = nil
    end
end
