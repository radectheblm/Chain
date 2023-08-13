_addon.author = 'Radec'
_addon.command = 'ch'
_addon.name = 'chain'
_addon.version = '2.4'

--Changelog
--v1: string builder, auto SC picking
--v2: list of commands, interuptable
--v2.1: last-ws detection for Sortie BDGH
--v2.2: fuzzy name matching for skillchains. fuzzyfind from superwarp, credit to Akaden and Lili 
--v2.3: toggle to fallback from helix to normal spell if helix cannot be cast
--v2.4: Added settings file

--TODO
--	manual builder, ie ch wind earth wind dark for sci det grav ala ongo. Maybe skip this? could just add them to the table

require('tables')
res = require('resources')
require('fuzzyfind')
config = require('config')

-- default settings

defaults = {}
defaults.default_helix = true --closes chains with helix1 to extend burst window. B/F Bosses are blocked from using this.
defaults.allow_helix_recast_fallback = true --2.3 feature, if helix is on recast, use a t1 insteal
defaults.announce_channel = 'party' --which channel to call out your actions in. 
defaults.default_chain = 'Fusion' --default choice when sc is not specified, and not a known mob
defaults.wait = {}
defaults.wait.post_ja = 1.3
defaults.wait.post_spell = 4.0
defaults.wait.post_helix_opener = 7.0
defaults.wait.post_helix = 8.0 --Works up to 9.5 for thunder-pyro-[settings.wait.post_helix]-iono, but is inconsistent. Less than 8.5 is safer

settings = config.load(defaults)

last_ws = {}

spells_to_chain = T{
	['Earth'] =		{normal="Stone",		helix="Geohelix"},
	['Water'] =		{normal="Water",		helix="Hydrohelix"},
	['Wind'] =		{normal="Aero",			helix="Anemohelix"},
	['Fire'] =		{normal="Fire",			helix="Pyrohelix"},
	['Ice'] =		{normal="Blizzard",		helix="Cryohelix"},
	['Lightning'] =	{normal="Thunder",		helix="Ionohelix"},
	['Dark'] =		{normal="Noctohelix",	helix="Noctohelix"},
	['Light'] =		{normal="Luminohelix",	helix="Luminohelix"},
}

--Alternate viable forms are commented out. The choice typically prevents absorbs, or avoid opening with a helix when possible
skillchain_steps = T{

	['Scission'] =      {"Fire","Earth"},
	--['Scission'] =      {"Wind","Earth"},

	['Reverberation'] = {"Earth","Water"},
	--['Reverberation'] = {"Light","Water"},

	['Detonation'] =    {"Lightning","Wind"},
	--['Detonation'] =    {"Earth","Wind"},
	--['Detonation'] =    {"Dark","Wind"},

	['Liquefaction'] =  {"Lightning","Fire"},
	--['Liquefaction'] =  {"Earth","Fire"}, --Equally viable, but lightning-fire are both light-side elements which could be a factor

	['Induration'] =    {"Water","Ice"},

	['Impaction'] =     {"Ice","Lightning"},
	--['Impaction'] =     {"Water","Lightning"},

	['Compression'] =   {"Ice","Dark"},
	--['Compression'] =   {"Light","Dark"},

	['Transfixion'] =   {"Dark","Light"},

	['Fusion'] =        {"Fire","Lightning"},
	['Gravitation'] =   {"Wind","Dark"},
	['Distortion'] =    {"Light","Earth"},
	['Fragmentation'] = {"Ice","Water"},

	['Liqfusion'] = 	{"Lightning","Fire","Lightning"},
	--['Liqfusion'] = 	{"Earth","Fire","Lightning"}, --Equally viable, but lightning-fire are both light-side elements which could be a factor
}

default_chains_by_mob_name = T{
	['Ghatjot'] = "Liqfusion",

	['Biune Porxie'] = "Liqfusion",

	['Cachaemic Bhoot'] = "Liqfusion",
	['Skomora'] = "Liqfusion",

	['Demisang Deleterious'] = 'Liqfusion',

	['Esurient Botulus'] = 'Liqfusion',
	['Dhartok'] = "Liqfusion",

	['Fetid Ixion'] = "Gravitation",

	['Gyvewrapped Naraka'] = "Liqfusion",
	['Triboulex'] = "Liqfusion",

	['Haughty Tulittia'] = "Liqfusion",

	['Yggdreant'] = "Fragmentation",
	['Rockfin'] = "Fragmentation",
	['Bztavian'] = "Induration",
	['Gabbrath'] = "Reverberation",
	['Cehuetzi'] = "Fusion",
	['Waktza'] = "Gravitation",
}

windower.register_event("addon command", function (...)
    local params = {...}

    for i,v in pairs(params) do params[i]=windower.convert_auto_trans(params[i]):lower() end
    for i,v in pairs(params) do params[i]=params[i]:lower() end

    local skillchain_name = 'auto'

    if #params == 1 then
	    if params[1] == "helix" then
	    	settings.default_helix = not settings.default_helix
	    	print("Using Helix closers: "..tostring(settings.default_helix))
	    	settings:save()
	    	return
	    elseif params[1] == "fallback" then
	    	settings.allow_helix_recast_fallback = not settings.allow_helix_recast_fallback
	    	print("Using alternatives when Helix unavailable: "..tostring(settings.allow_helix_recast_fallback))
	    	settings:save()
	    	return
	    elseif skillchain_steps[firstToUpper(params[1])] ~= nil then
	    	skillchain_name = firstToUpper(params[1])
	    elseif params[1] == "lf" or params[1] == "3step" then
	    	skillchain_name = "Liqfusion"
	    else
	    	skillchain_name = fmatch(params[1], keys(skillchain_steps))
	    end
	end

	make_skillchain(skillchain_name, settings.default_helix)
end)

windower.register_event("load", function (...)
	local player = windower.ffxi.get_player()
	while not player do
		coroutine.sleep(5)
		player = windower.ffxi.get_player()
	end
	settings = config.load('data/'..player['name']..'.xml', defaults)
end)

windower.register_event("login", function (...)
	local player = windower.ffxi.get_player()
	while not player do
		coroutine.sleep(5)
		player = windower.ffxi.get_player()
	end
	settings = config.load('data/'..player['name']..'.xml', defaults)
	last_ws = {}
end)

windower.register_event("action", function (act)
	local mabils = res.monster_abilities
	local actor = windower.ffxi.get_mob_by_id(act['actor_id'])

	if act['category'] == 11 and mabils[act['param']] then
		last_ws[actor['index']] = mabils[act['param']]['en']
	end
end)

windower.register_event('zone change', function(new_id, old_id)
	--Reset last WS history
	last_ws = {}
end)

function keys(tab)
	local keyset={}
	local n=0

	for k,v in pairs(tab) do
		n=n+1
		keyset[n]=k
	end
	return keyset
end

function bdgh_skillchain(index)
	local elemental_ws_to_sc = T{
		--['Eroding Flesh'] = 'Detonation',
		['Eroding Flesh'] = 'Fragmentation',

		--['Flashflood'] = 'Impaction',
		['Flashflood'] = 'Fragmentation',

		['Chokehold'] = 'Induration',
		['Tearing Gust'] = 'Induration',
		['Undulating Shockwave'] = 'Induration', --Shockwave is a Thunder WS, but causes the switch to wind mode

		['Flaming Kick'] = 'Reverberation',
		--['Flaming Kick'] = 'Distortion', --Helix opener is slower

		--['Icy Grasp'] = 'Liquefaction',
		--['Icy Grasp'] = 'Fusion',
		['Icy Grasp'] = 'Liqfusion',

		['Zap'] = 'Scission',
		['Concussive Shock'] = 'Scission',
		['Shrieking Gale'] = 'Scission', --Gale is a wind WS, but causes the switch to thunder mode

		--['Fulminous Smash'] = 'Scission',
		['Fulminous Smash'] = 'Gravitation'
	}

	if last_ws[index] then
		for mob_ws,counter_chain in pairs(elemental_ws_to_sc) do
			if mob_ws == last_ws[index] then
				--print("Based on last tracked WS of "..last_ws[index].." chain is "..counter_chain)
				return counter_chain
			end
		end
	end
	return 'unknown'
end

function firstToUpper(str)
    return (str:gsub("^%l", string.upper))
end

--Return a string for all the steps needed to make the skillchain
function make_skillchain(chain_name, use_helix)
	local player = windower.ffxi.get_player()
	if player['target_index'] == nil then
		print("No target")
		return
	end
	if player['main_job'] ~= "SCH" then
		print("You're not a SCH, closing")
		windower.send_command("lua u chain")
	end

	local target_name = windower.ffxi.get_mob_by_index(player['target_index'])['name']
	local buffs = T(player['buffs'])
	local abil_recasts = T(windower.ffxi.get_ability_recasts())
	local spell_recasts = T(windower.ffxi.get_spell_recasts())


	--Don't MPK tanks
	if S{'Leshonn','Gartell'}:contains(target_name) then
		use_helix = false
	end

	if chain_name == 'auto' then
		if default_chains_by_mob_name[target_name] ~= nil then
			chain_name = default_chains_by_mob_name[target_name]
		elseif S{'Leshonn','Degei','Gartell','Aita'}:contains(target_name) then
			chain_name = bdgh_skillchain(player['target_index'])
		else
			chain_name = settings.default_chain
		end
	end

	--Account for immanence already existing
	local active_immanence = 0
	if buffs:contains(res.buffs:with('en', "Immanence")['id']) then
		active_immanence = 33
	end

	if skillchain_steps[chain_name] ~= nil then
		local execution_time = 0
		local failure_reason = nil
		local command_list = T{}


		if not (buffs:contains(res.buffs:with('en', "Dark Arts")['id']) or buffs:contains(res.buffs:with('en', "Addendum: Black")['id'])) then
			if abil_recasts[res.ability_recasts:with('en', 'Dark Arts')['id']] <= execution_time then
				command_list[#command_list+1] = "DarkArts"
				execution_time = execution_time + 1.3
			else
				failure_reason = "Unable to reach Dark Arts"
			end
		end

		if not failure_reason then
			--Check that each command will be ready when called for
			for step,element in pairs(skillchain_steps[chain_name]) do

				if abil_recasts[res.ability_recasts:with('en', 'Stratagems')['id']] < active_immanence+33*(5-step)+execution_time then
					command_list[#command_list+1] = "Immanence"
					execution_time = execution_time + settings.wait.post_ja
				else
					failure_reason = "Unable to use Immanence #"..step
					break
				end

				if step == 1 or not use_helix then
					spell = spells_to_chain[element]['normal']
				else
					spell = spells_to_chain[element]['helix']
					if spell_recasts[res.spells:with('en', spell)['id']]/60 > execution_time and settings.allow_helix_recast_fallback then
						spell = spells_to_chain[element]['normal']
					end
				end
				if spell_recasts[res.spells:with('en', spell)['id']]/60 < execution_time then
					command_list[#command_list+1] = spell
					if spell:find("helix") then
						if step == 1 then
							execution_time = execution_time + settings.wait.post_helix_opener
						else
							execution_time = execution_time + settings.wait.post_helix
						end
					else
						execution_time = execution_time + settings.wait.post_spell
					end
				else
					failure_reason = "Unable to use "..spell
					break
				end
			end
		end

		if failure_reason then
			print(failure_reason)
		else
			run_commands(command_list, 1, chain_name)
		end
	else
		print(chain_name.." is not a valid chain")
	end
end

function run_commands(command_list, command_index, chain_name)
	if command_index <= #command_list then
		local current_command = command_list[command_index]
		local player = windower.ffxi.get_player()

		local buffs = T(windower.ffxi.get_player()['buffs'])
		local blocking_status = T{'KO','sleep','paralysis','petrification','stun','charm','amnesia','terror','Lullaby','encumbrance','silence','mute'}
		
		for _,v in pairs(blocking_status) do
			if buffs:contains(res.buffs:with('en', v)['id']) then
				print("Chain: Stopping execution for status "..v)
				return
			end
		end

		if player['target_index'] == nil then
			print("Chain: Stopping execution, no target")
			return
		end

		if buffs:contains(res.buffs:with('en', "Immanence")['id']) and current_command == "Immanence" and command_index <= 2 then
			--Already had immanence up, skip to next action. 
			--Only valid for the first Imma, others might be buffs updating slow.
			run_commands(command_list,command_index+1, chain_name)
		else
			windower.send_command(current_command)

			if T{'Immanence','DarkArts'}:contains(current_command) then
				coroutine.sleep(settings.wait.post_ja)
			else
				if command_index <= 3 then --da-imma-OPENER or imma-OPENER-imma
					windower.send_command("input /"..settings.announce_channel.." Opening "..chain_name..": "..current_command)
				else
					windower.send_command("input /"..settings.announce_channel.." "..chain_name..": "..current_command)
				end
				if current_command:find('helix') then
					if command_index <= 3 then
						coroutine.sleep(settings.wait.post_helix_opener)
					else
						coroutine.sleep(settings.wait.post_helix)
					end
				else --Non-helix spell
					coroutine.sleep(settings.wait.post_spell)
				end
			end

			run_commands(command_list,command_index+1, chain_name)
		end
	end
end