-- Mouse drags in Noita swap the two spells' positions atomically: there is no
-- frame where the dragged spell is "in limbo", so its identity can't be read
-- off the entity graph. Instead, compare where the mouse was on press vs now
-- against where each spell moved: the dragged spell is the one that moved in
-- the same direction the mouse did. Same-wand moves compare slot_index along
-- X (a wand's slots are a single left-to-right row); cross-container moves
-- compare container_rank along Y (the spell bag row sits above the stacked
-- wand boxes on screen). Returns nil if the mouse barely moved or the signs
-- don't clearly agree, in which case the caller keeps the vanilla swap.
local function resolve_drag_identity_from_mouse(baseline, spell_one, spell_two, press_x, press_y, release_x, release_y)
	if not press_x then
		return nil
	end

	local location_one = baseline.spell_locations[spell_one]
	local location_two = baseline.spell_locations[spell_two]

	local rank_one, rank_two, mouse_delta
	if location_one.container == location_two.container then
		rank_one, rank_two = location_one.slot_index, location_two.slot_index
		mouse_delta = release_x - press_x
	else
		rank_one = baseline.container_rank[location_one.container]
		rank_two = baseline.container_rank[location_two.container]
		mouse_delta = release_y - press_y
	end

	SpellShift.debug_log(string.format("mouse heuristic: rank_one=%s rank_two=%s mouse_delta=%.1f",
		tostring(rank_one), tostring(rank_two), mouse_delta))

	if math.abs(mouse_delta) < SpellShift.MIN_DRAG_DISTANCE_PIXELS then
		return nil
	end

	-- The dragged spell is whichever one moved toward higher rank when the
	-- mouse moved that way, or toward lower rank when it moved the other way.
	local one_moved_to_higher_rank = rank_one < rank_two
	if (mouse_delta > 0) == one_moved_to_higher_rank then
		return spell_one, spell_two
	else
		return spell_two, spell_one
	end
end

-- Interprets a two-spell position exchange as "the player dragged one spell
-- onto the other" and identifies which one was dragged, using the mouse's
-- drag direction. If that's inconclusive, the caller keeps the vanilla swap
-- rather than guess.
function SpellShift.classify_swap(baseline, current_snapshot, moved, appeared, disappeared, press_x, press_y, release_x, release_y)
	if #appeared > 0 or #disappeared > 0 or #moved ~= 2 then
		return nil
	end

	local spell_one, spell_two = moved[1], moved[2]
	local dragged_spell, displaced_spell = resolve_drag_identity_from_mouse(
		baseline, spell_one, spell_two, press_x, press_y, release_x, release_y
	)
	if not dragged_spell then
		return nil -- ambiguous which spell was dragged; keep the vanilla swap
	end

	local dragged_new_location = current_snapshot.spell_locations[dragged_spell]
	if not dragged_new_location.is_wand_slot then
		return nil -- dropped into the spell bag; the bag keeps vanilla behavior
	end

	local origin_location = baseline.spell_locations[dragged_spell]
	local origin_slot_index_on_target_wand = nil
	if origin_location.container == dragged_new_location.container then
		origin_slot_index_on_target_wand = origin_location.slot_index
	end

	return {
		dragged_spell = dragged_spell,
		displaced_spell = displaced_spell,
		target_wand = dragged_new_location.container,
		target_slot_index = dragged_new_location.slot_index,
		origin_slot_index_on_target_wand = origin_slot_index_on_target_wand,
	}
end
