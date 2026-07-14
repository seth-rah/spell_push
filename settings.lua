dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "spell_shift"
mod_settings_version = 1
mod_settings = {
	{
		category_id = "notice",
		ui_name = [[
Holding Left Alt while dropping a spell onto a wand switches between
Spell Push's insert-and-push behaviour and vanilla Noita's swap.
Choose which one holding Left Alt activates below.
]],
		settings = {},
	},
	{
		id = "left_alt_behaviour",
		ui_name = "Left alt behaviour",
		value_default = "vanilla",
		values = {
			-- Display text only -- the stored value stays "spell_shift" so an
			-- existing local preference isn't silently reset by the rename.
			{ "spell_shift", "Hold for spell push" },
			{ "vanilla", "Hold for vanilla Noita behaviour" },
		},
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
}

function ModSettingsUpdate(init_scope)
	mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
	return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
	mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
