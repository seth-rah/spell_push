-- Computes the slot layout a wand should end up with after inserting
-- dragged_spell at target_slot_index, per the mod's shift rule: prefer
-- shifting the displaced run toward a gap to the right, otherwise to the
-- left. Returns nil if the wand has no free slot anywhere, in which case
-- the caller should leave the game's own vanilla swap in place.
function SpellShift.compute_insert_layout(baseline_wand, dragged_spell, origin_slot_index, target_slot_index)
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

-- A spell counts as a "bystander" if the insert would move it even though it
-- wasn't the spell the player dragged or the one it landed on. If any
-- bystander is frozen, the wand can't actually be rearranged this way.
function SpellShift.has_frozen_bystander(baseline_wand, new_layout, dragged_spell)
	for slot_index, spell in pairs(baseline_wand.spells_by_slot) do
		if spell ~= dragged_spell then
			local new_slot_index = nil
			for candidate_slot, candidate_spell in pairs(new_layout) do
				if candidate_spell == spell then
					new_slot_index = candidate_slot
					break
				end
			end
			if new_slot_index ~= slot_index and SpellShift.is_frozen(spell) then
				return true
			end
		end
	end
	return false
end

-- Rewrites the wand's slots to match new_layout. ItemComponent.inventory_slot
-- is documented as only a "preferred" slot, not an authoritative one -- the
-- wand's actual displayed order also depends on child order in the entity
-- tree. Setting inventory_slot alone left the engine's own auto-placement
-- (triggered by EntityAddChild) winning ties, so every spell in the new
-- layout is removed and re-added in the exact order it should end up in,
-- which pins down child order too, then inventory_slot is set to match.
function SpellShift.apply_insert_layout(player, wand, new_layout)
	local ordered_slots = {}
	for slot_index in pairs(new_layout) do
		table.insert(ordered_slots, slot_index)
	end
	table.sort(ordered_slots)

	for _, slot_index in ipairs(ordered_slots) do
		local spell = new_layout[slot_index]
		EntityRemoveFromParent(spell)
		EntityAddChild(wand, spell)
		SpellShift.set_slot_index(spell, slot_index)
	end

	GameRegenItemActionsInContainer(wand)
	GameRegenItemActionsInPlayer(player)

	local inventory_component = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
	if inventory_component then
		pcall(ComponentSetValue2, inventory_component, "mForceRefresh", true)
	end
end
