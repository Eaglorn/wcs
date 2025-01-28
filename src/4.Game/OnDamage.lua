do
    OnInit.final(function()
        local trigger = CreateTrigger()
        TriggerRegisterAnyUnitEventBJ(trigger, EVENT_PLAYER_UNIT_DAMAGED)
        TriggerAddCondition(trigger, Condition(function()
            local source = GetEventDamageSource()
            local target = BlzGetEventDamageTarget()
            local damage = GetEventDamage()
            --local damagetype
            --local attacktype

            if damage > 0 then
                --damagetype = BlzGetEventDamageType()
                --attacktype = BlzGetEventAttackType()
                AddUnitBonus(target, BONUS_AGILITY, 1)
                AddUnitBonus(target, BONUS_STRENGTH, 1)
                AddUnitBonus(target, BONUS_INTELLIGENCE, 1)
                AddUnitBonus(target, BONUS_LIFE_STEAL, 0.01)
                AddUnitBonus(target, BONUS_CRITICAL_CHANCE, 0.01)
                AddUnitBonus(target, BONUS_CRITICAL_DAMAGE, 0.01)
                AddUnitBonus(target, BONUS_ATTACK_SPEED, 0.01)
                AddUnitBonus(target, BONUS_HEALTH_REGEN, 0.01)
                AddUnitBonus(target, BONUS_HEALTH, 1)
                AddUnitBonus(target, BONUS_ARMOR, 1)
                AddUnitBonus(target, BONUS_DAMAGE, 1)
                AddUnitBonus(target, BONUS_TENACITY, 0.01)
                StunUnit(source, 0.5, nil, nil, true)
            elseif damage < 0 then
            end
        end))
    end)
    OnInit.final(function()
        local trigger = CreateTrigger()
        TriggerRegisterAnyUnitEventBJ(trigger, EVENT_PLAYER_UNIT_DAMAGED)
        TriggerAddCondition(trigger, Condition(function()
            local target = BlzGetEventDamageTarget()
            local damage = GetEventDamage()
            local text   = I2S(R2I(damage))

            if damage > 0 then
                ArcingTextTag("|cffff0000" .. text .. "|r", target)
            elseif damage < 0 then
                ArcingTextTag("|cff00ff00 +" .. text .. "|r", target)
            end
        end))
    end)
end
