-- Computes the slot layout a wand should end up with after inserting
-- dragged_spell at target_slot_index, per the mod's push rule: prefer
-- pushing the displaced run toward a gap to the right, otherwise to the
-- left. Returns nil if the wand has no free slot anywhere, in which case
-- the caller should leave the game's own vanilla swap in place.
function SpellPush.compute_insert_layout(baseline_wand, dragged_spell, origin_slot_index, target_slot_index)
	local slots = {}
	for slot_index, spell in pairs(baseline_wand.spells_by_slot) do
		slots[slot_index] = spell
	end
	if origin_slot_index then
		slots[origin_slot_index] = nil -- same-wand move: free the spell's old slot before inserting
	end

	local gap = nil
	for slot_index = target_slot_index + 1, baseline_wand.capacity - 1 do
		if slots[slot_index] == nil then
			gap = slot_index
			break
		end
	end

	if gap then
		for slot_index = gap - 1, target_slot_index, -1 do
			slots[slot_index + 1] = slots[slot_index]
		end
	else
		for slot_index = target_slot_index - 1, 0, -1 do
			if slots[slot_index] == nil then
				gap = slot_index
				break
			end
		end
		if not gap then
			return nil -- wand is completely full; keep the vanilla swap
		end
		for slot_index = gap + 1, target_slot_index do
			slots[slot_index - 1] = slots[slot_index]
		end
	end

	slots[target_slot_index] = dragged_spell
	return slots
end

-- Rewrites the wand's slots to match new_layout. ItemComponent.inventory_slot
-- is documented as only a "preferred" slot, not an authoritative one -- the
-- wand's actual displayed order also depends on child order in the entity
-- tree. Setting inventory_slot alone left the engine's own auto-placement
-- (triggered by EntityAddChild) winning ties, so every spell in the new
-- layout is removed and re-added in the exact order it should end up in,
-- which pins down child order too, then inventory_slot is set to match.
function SpellPush.apply_insert_layout(player, wand, new_layout)
	local ordered_slots = {}
	for slot_index in pairs(new_layout) do
		table.insert(ordered_slots, slot_index)
	end
	table.sort(ordered_slots)

	-- GameRegenItemActions* below rebuilds each action from its gun_actions.lua
	-- definition, which refills limited-use spells to full charges. Save the
	-- real counts up front and put them back afterward.
	local saved_uses_remaining = {}
	for _, spell in pairs(new_layout) do
		local item_component = SpellPush.get_item_component(spell)
		saved_uses_remaining[spell] = ComponentGetValue2(item_component, "uses_remaining")
	end

	for _, slot_index in ipairs(ordered_slots) do
		local spell = new_layout[slot_index]
		EntityRemoveFromParent(spell)
		EntityAddChild(wand, spell)
		SpellPush.set_slot_index(spell, slot_index)
	end

	GameRegenItemActionsInContainer(wand)
	GameRegenItemActionsInPlayer(player)

	for spell, uses_remaining in pairs(saved_uses_remaining) do
		local item_component = SpellPush.get_item_component(spell)
		ComponentSetValue2(item_component, "uses_remaining", uses_remaining)
	end

	local inventory_component = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
	if inventory_component then
		pcall(ComponentSetValue2, inventory_component, "mForceRefresh", true)
	end
end
