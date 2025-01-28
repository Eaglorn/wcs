TargetOrders = { "innerfire", "slow", "heal", "controlmagic", "invisibility", "magicleash", "spellsteal", "polymorph",
    "repair", "thunderbolt", "banish", "holybolt", "load", "unstableconcoctoin", "spirintlink",
    "bloodlust", "ensnare", "devour", "purge", "lightingshield", "healingwave", "hex", "chainlightning", "antimagicshell",
    "unholyfrenzy", "possession", "web", "absorbmana", "curse", "restoration", "cripple", "frostarmor",
    "deathpact", "sleep", "darkritual", "faeriefire", "renew", "autodispel", "cyclone", "entanglingroots",
    "flamingarrows", "manaburn", "shadowstrike", "creepthunderbolt", "mindrot", "deathcoil",
    "parasite", "charm", "creepdevour", "forkedlighting", "cripple", "blackarrow", "acidbomb", "doom", "soulburn",
    "transmute", "rejuvination" }

PointOrders = { "flare", "dispel", "cloudoffog", "flamestrike", "blizzard", "healingward", "stasistrap", "evileye",
    "farsight", "eathquake", "ward", "serpentward", "shockwave", "inferno", "impale", "deathanddecay", "carrionswarm",
    "detonate", "forceofnature", "blink", "selfdestruct", "silence", "rainoffire", "breathofirre", "volcano", "stampede",
    "healingspray", "clusterrockets", "summonfactory", "drunkenhaze" }

ImmediateOrders = { "defend", "magicdefense", "militia", "townbellon", "avatar", "divineshield", "resurrection",
    "massteleport", "waterelemental", "thunderclap", "summonphoenix", "etherealform", "berserk",
    "battlestations", "corporealform", "whirlwind", "stomp", "spiritwolf", "locustswarm", "mirrorimage", "voodoo",
    "windwalk", "raisedead", "recharge", "replenish", "borrow", "stoneform", "cannibalize", "sphinksform",
    "replenishlife",
    "replenishmana", "carrionscarabs", "animatedead", "coupletarget", "manaflareon", "vengeance", "ravenform", "bearform",
    "taunt", "roar", "ambush", "fanofknives", "starfall", "metamorphosis", "immolation",
    "tranquility", "monsoon", "frenzy", "howlofterror", "manashield", "battleroar", "elementalfury", "wateryminion",
    "slimemonster", "robogoblin", "tornado", "chemicalrage" }
---@param u unit
---@param x real
---@param y real
---@param target unit
function Cast(u, x, y, target)
    if UnitAlive(u) then
        AllPoint(u, x, y)
        AllTarget(u, target)
        AllImmediate(u)
    end
end

function AllImmediate(u)
    for i = 1, #ImmediateOrders do
        --print(ImmediateOrders[i].." is immediate")
        IssueImmediateOrder(u, ImmediateOrders[i])
    end
end

function AllPoint(u, x, y)
    for i = 1, #PointOrders do
        --	print(PointOrders[i].." is point")
        IssuePointOrder(u, PointOrders[i], x, y)
    end
end

function AllTarget(u, target)
    for i = 1, #TargetOrders do
        --print(TargetOrders[i].." is target")
        IssueTargetOrder(u, TargetOrders[i], target)
    end
end
