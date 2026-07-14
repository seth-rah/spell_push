-- keycodes.lua lives inside the game's packed data.wak, not on disk, but
-- dofile_once resolves it through the game's own virtual filesystem. It's a
-- game-owned file this mod doesn't control, so the load is wrapped in pcall;
-- the numeric fallback below covers both a failed load and a renamed constant.
local keycodes_loaded_ok = pcall(dofile_once, "data/scripts/debug/keycodes.lua")

-- Shared namespace for this mod's submodules. Noita mods share one global
-- Lua environment, so everything below is namespaced under this table
-- instead of adding bare global names. Submodules assign their functions as
-- SpellShift.foo = function(...) ... end (not "return {...}"): dofile_once
-- only runs a given path once per Lua context, so a hot-reload's second call
-- for the same path is a documented no-op that returns nothing -- capturing
-- a return value into this table would get silently overwritten with nil.
-- Bare-global assignment doesn't have that failure mode: a no-op reload just
-- leaves the already-assigned functions in place.
SpellShift = SpellShift or {}

-- Flip to true to trace drag detection/resolution on-screen and in logger.txt.
local DEBUG = false

function SpellShift.debug_log(message)
	if DEBUG then
		print("spell_shift: " .. message)
		GamePrint("spell_shift: " .. message)
	end
end

if not keycodes_loaded_ok then
	SpellShift.debug_log("keycodes.lua failed to load; using numeric fallback")
end

SpellShift.MIN_DRAG_DISTANCE_PIXELS = 3 -- ignore mouse jitter smaller than this when reading drag direction

dofile_once("mods/spell_shift/files/scripts/snapshot.lua")
dofile_once("mods/spell_shift/files/scripts/layout.lua")
dofile_once("mods/spell_shift/files/scripts/drag.lua")

local BYPASS_KEYBOARD_KEY = Key_lalt or 226 -- SDL_SCANCODE_LALT
local MOUSE_LEFT_BUTTON = Mouse_left or 1 -- SDL_BUTTON_LEFT
local PENDING_CORRECTION_FRAMES = 5

-- drag_state holds everything needed to turn the vanilla swap the game is
-- about to perform into an insert. It is rebuilt from scratch whenever the
-- inventory closes, so nothing here needs to survive a save/load.
local drag_state = nil

-- Where the mouse was the last time the left button went down, kept across
-- frames independently of drag_state so it still reflects the start of the
-- current drag by the time that drag's swap is detected and resolved.
local last_press_x, last_press_y = nil, nil

-- The game's own drag-and-drop resolution keeps adjusting a wand's slots for
-- a couple of frames after the drop, even after apply_insert_layout has
-- already written the intended layout. pending_correction re-asserts that
-- layout on every frame for a short window afterward, so the game's delayed
-- adjustment doesn't silently win.
local pending_correction = nil

local function alt_is_held()
	return InputIsKeyDown(BYPASS_KEYBOARD_KEY)
end

local function fresh_drag_state(baseline_snapshot, alt_held_now)
	return {
		baseline = baseline_snapshot,
		alt_was_held_last_frame = alt_held_now,
	}
end

local function try_convert_swap_to_insert(player, baseline, swap)
	local baseline_wand = baseline.wands[swap.target_wand]
	if not baseline_wand then
		SpellShift.debug_log("skip: target wand not in baseline")
		return
	end

	local new_layout = SpellShift.compute_insert_layout(
		baseline_wand,
		swap.dragged_spell,
		swap.origin_slot_index_on_target_wand,
		swap.target_slot_index
	)
	if not new_layout then
		SpellShift.debug_log("skip: wand has no free slot, vanilla swap stands")
		return
	end

	if SpellShift.has_frozen_bystander(baseline_wand, new_layout, swap.dragged_spell) then
		SpellShift.debug_log("skip: a spell in the shift run is frozen")
		return
	end

	SpellShift.debug_log("applying insert layout")
	SpellShift.apply_insert_layout(player, swap.target_wand, new_layout)
	pending_correction = {
		wand = swap.target_wand,
		layout = new_layout,
		frames_left = PENDING_CORRECTION_FRAMES,
	}
end

local function poll()
	local player = SpellShift.get_player()
	if not player or not GameIsInventoryOpen() then
		drag_state = nil
		last_press_x, last_press_y = nil, nil
		pending_correction = nil
		return
	end

	if pending_correction then
		SpellShift.debug_log("re-asserting pending correction, frames_left=" .. pending_correction.frames_left)
		SpellShift.apply_insert_layout(player, pending_correction.wand, pending_correction.layout)
		pending_correction.frames_left = pending_correction.frames_left - 1
		if pending_correction.frames_left <= 0 then
			pending_correction = nil
		end
	end

	if InputIsMouseButtonJustDown(MOUSE_LEFT_BUTTON) then
		last_press_x, last_press_y = InputGetMousePosOnScreen()
	end

	local alt_held_now = alt_is_held()
	local current_snapshot = SpellShift.take_snapshot(player)

	if not drag_state then
		SpellShift.debug_log("inventory opened, baseline established")
		drag_state = fresh_drag_state(current_snapshot, alt_held_now)
		return
	end

	local moved, appeared, disappeared = SpellShift.diff_snapshots(drag_state.baseline, current_snapshot)

	if #moved == 0 and #appeared == 0 and #disappeared == 0 then
		drag_state.alt_was_held_last_frame = alt_held_now
		return
	end

	SpellShift.debug_log(string.format("diff: moved=%d appeared=%d disappeared=%d",
		#moved, #appeared, #disappeared))

	local release_x, release_y = InputGetMousePosOnScreen()
	local swap = SpellShift.classify_swap(drag_state.baseline, current_snapshot, moved, appeared, disappeared,
		last_press_x, last_press_y, release_x, release_y)

	if not swap then
		SpellShift.debug_log("could not classify as a swap; leaving vanilla result in place")
	else
		-- Alt held on either the drop frame or the frame before (detection lags
		-- the drop by a frame) flips which behavior is "active" for this drop.
		-- "vanilla" (default): insert-and-shift unless Alt is held. "spell_shift": the reverse.
		local alt_held = alt_held_now or drag_state.alt_was_held_last_frame
		local hold_alt_to_activate = ModSettingGet("spell_shift.left_alt_behaviour") == "spell_shift"
		local should_insert = (alt_held == hold_alt_to_activate)

		if not should_insert then
			SpellShift.debug_log("mode says vanilla; leaving swap in place")
		else
			SpellShift.debug_log(string.format("converting swap: dragged=%s displaced=%s wand=%s target_slot=%s origin_slot=%s",
				tostring(swap.dragged_spell), tostring(swap.displaced_spell), tostring(swap.target_wand),
				tostring(swap.target_slot_index), tostring(swap.origin_slot_index_on_target_wand)))
			try_convert_swap_to_insert(player, drag_state.baseline, swap)
		end
	end

	-- Whatever happened, the game's own state is authoritative again now.
	drag_state = fresh_drag_state(SpellShift.take_snapshot(player), alt_held_now)
end

function OnPlayerSpawned(player_entity)
	drag_state = nil
end

function OnWorldPostUpdate()
	poll()
end

function OnPausePreUpdate()
	poll()
end
