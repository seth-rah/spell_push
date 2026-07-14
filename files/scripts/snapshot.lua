function SpellShift.get_player()
	local players = EntityGetWithTag("player_unit")
	return players and players[1]
end

local function find_child_named(entity, name)
	for _, child in ipairs(EntityGetAllChildren(entity) or {}) do
		if EntityGetName(child) == name then
			return child
		end
	end
	return nil
end

local function get_item_component(spell)
	return EntityGetFirstComponentIncludingDisabled(spell, "ItemComponent")
end

-- A spell is any entity with both an ItemComponent and an ItemActionComponent.
local function is_spell(entity)
	local item_component = get_item_component(entity)
	local action_component = EntityGetFirstComponentIncludingDisabled(entity, "ItemActionComponent")
	return item_component ~= nil and action_component ~= nil
end

function SpellShift.is_frozen(spell)
	local item_component = get_item_component(spell)
	return item_component ~= nil and ComponentGetValue2(item_component, "is_frozen") == true
end

local function slot_index_of(spell)
	local item_component = get_item_component(spell)
	local x = ComponentGetValue2(item_component, "inventory_slot")
	return x
end

function SpellShift.set_slot_index(spell, slot_index)
	local item_component = get_item_component(spell)
	ComponentSetValue2(item_component, "inventory_slot", slot_index, 0)
end

-- Builds {capacity, spells_by_slot = {[slot_index] = spell_entity}} for one
-- wand. Always-cast spells live outside the slot sequence and are excluded.
local function snapshot_wand(wand)
	local spells_by_slot = {}
	for _, child in ipairs(EntityGetAllChildren(wand) or {}) do
		local item_component = get_item_component(child)
		if item_component and is_spell(child) and not ComponentGetValue2(item_component, "permanently_attached") then
			spells_by_slot[slot_index_of(child)] = child
		end
	end
	return { capacity = EntityGetWandCapacity(wand), spells_by_slot = spells_by_slot }
end

-- A full snapshot of the player's wands and spell bag: which wand or bag each
-- spell currently sits in, and at which slot. This is the only state the mod
-- tracks; everything else is derived from diffing two of these.
--
-- container_rank records each wand/bag's on-screen top-to-bottom order (wands
-- appear in inventory_quick's child order, which matches their hotbar slots
-- and thus their vertical position among the stacked wand detail boxes; the
-- spell bag row is drawn above all of them). This lets a cross-container
-- drag be compared on a single axis, the same way slot_index compares
-- positions within one wand.
function SpellShift.take_snapshot(player)
	local snapshot = { wands = {}, spell_locations = {}, container_rank = {} }
	local next_container_rank = 0

	local bag = find_child_named(player, "inventory_full")
	if bag then
		snapshot.container_rank[bag] = next_container_rank
		next_container_rank = next_container_rank + 1
	end

	local quick_inventory = find_child_named(player, "inventory_quick")
	for _, item in ipairs(EntityGetAllChildren(quick_inventory) or {}) do
		if EntityHasTag(item, "wand") then
			local wand_snapshot = snapshot_wand(item)
			snapshot.wands[item] = wand_snapshot
			snapshot.container_rank[item] = next_container_rank
			next_container_rank = next_container_rank + 1
			for slot_index, spell in pairs(wand_snapshot.spells_by_slot) do
				snapshot.spell_locations[spell] = { container = item, is_wand_slot = true, slot_index = slot_index }
			end
		end
	end

	if bag then
		for _, spell in ipairs(EntityGetAllChildren(bag) or {}) do
			if is_spell(spell) then
				snapshot.spell_locations[spell] = { container = bag, is_wand_slot = false, slot_index = slot_index_of(spell) }
			end
		end
	end

	return snapshot
end

-- Compares two snapshots by spell identity and returns which spells moved to
-- a different container/slot, which are new, and which are gone.
function SpellShift.diff_snapshots(before, after)
	local moved, disappeared = {}, {}
	for spell, before_location in pairs(before.spell_locations) do
		local after_location = after.spell_locations[spell]
		if not after_location then
			table.insert(disappeared, spell)
		elseif after_location.container ~= before_location.container or after_location.slot_index ~= before_location.slot_index then
			table.insert(moved, spell)
		end
	end

	local appeared = {}
	for spell in pairs(after.spell_locations) do
		if not before.spell_locations[spell] then
			table.insert(appeared, spell)
		end
	end

	return moved, appeared, disappeared
end
