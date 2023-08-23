_addon.author = 'Radec'
_addon.command = 'ch'
_addon.name = 'chain'
_addon.version = '2.8'

--Changelog
--v1: string builder, auto SC picking
--v2: list of commands, interuptable
--v2.1: last-ws detection for Sortie BDGH
--v2.2: fuzzy name matching for skillchains. fuzzyfind from superwarp, credit to Akaden and Lili 
--v2.3: toggle to fallback from helix to normal spell if helix cannot be cast
--v2.4: Added settings file
--v2.5: Adjust print feedback, add verbosity setting
--v2.6: Skillchain combos, mobs defaults, spell selection moved to settings. Plans for runtime chain builder scrapped, users can define chains in the settings xml
--v2.7: Allow for annouce_channel to change without manual xml file edit, Allow default_chain to change without manual xml file edit. Validates against existing defined chains, no fuzzy match here.
--v2.8: 
	--Adjust handling of skillchain steps to be valid xml. Now stored as <Name>Step1,Step2,...StepN</Name>. Steps must be valid elements as show in chain_spells, and properly capitalized. 
	--Fuzzy matching applied to default_chain.
	--Helix blocking extended to include HaughtyTulittia
	--Status command added to list current setting values
	--Feedback channel, announce channel, and verbosity show acceptable values when an invalid value is chosen


require('tables')
require('fuzzyfind')
res = require('resources')
config = require('config')

-- default settings

defaults = {}
defaults.IO = {}
defaults.IO.default_helix = true --closes chains with helix1 to extend burst window. B/F Bosses, HaughtyTulittia are blocked from using this.
defaults.IO.allow_helix_recast_fallback = true --2.3 feature, if helix is on recast, use a t1 insteal
defaults.IO.announce_channel = 'party' --which channel to call out your actions in. 
defaults.IO.default_chain = 'Fusion' --default choice when sc is not specified, and not a known mob
defaults.IO.verbosity = 1 --0 = low: Only settings changed messages. 1 = medium: spell/ja/command failure messages and settings changed messages. 2 = high: all messages and commands/delays shown
defaults.IO.feedback_channel = 'console' --console: print() statements, chat: add_to_chat() statements

defaults.wait = {}
defaults.wait.post_ja = 1.3
defaults.wait.post_spell = 4.0
defaults.wait.post_helix_opener = 7.0
defaults.wait.post_helix = 8.0 --Works up to 9.5 for thunder-pyro-[settings.wait.post_helix]-iono, but is inconsistent. Less than 8.5 is safer

defaults.skillchains = {}
defaults.skillchains.Scission = "Fire,Earth"
defaults.skillchains.Reverberation = "Earth,Water"
defaults.skillchains.Detonation = "Lightning,Wind"
defaults.skillchains.Liquefaction = "Lightning,Fire"
defaults.skillchains.Induration = "Water,Ice"
defaults.skillchains.Impaction = "Ice,Lightning"
defaults.skillchains.Compression = "Ice,Dark"
defaults.skillchains.Transfixion = "Dark,Light"
defaults.skillchains.Fusion = "Fire,Lightning"
defaults.skillchains.Gravitation = "Wind,Dark"
defaults.skillchains.Distortion = "Light,Earth"
defaults.skillchains.Fragmentation = "Ice,Water"
defaults.skillchains.Liqfusion = "Lightning,Fire,Lightning"

defaults.chain_by_mob = {}
defaults.chain_by_mob.Ghatjot = "Liqfusion"
defaults.chain_by_mob.BiunePorxie = "Liqfusion"
defaults.chain_by_mob.CachaemicBhoot = "Liqfusion"
defaults.chain_by_mob.Skomora = "Liqfusion"
defaults.chain_by_mob.DemisangDeleterious = "Liqfusion"
defaults.chain_by_mob.EsurientBotulus = "Liqfusion"
defaults.chain_by_mob.Dhartok = "Liqfusion"
defaults.chain_by_mob.FetidIxion = "Gravitation"
defaults.chain_by_mob.GyvewrappedNaraka = "Liqfusion"
defaults.chain_by_mob.Triboulex = "Liqfusion"
defaults.chain_by_mob.HaughtyTulittia = "Liqfusion"
defaults.chain_by_mob.Yggdreant = "Fragmentation"
defaults.chain_by_mob.Rockfin = "Fragmentation"
defaults.chain_by_mob.Bztavian = "Induration"
defaults.chain_by_mob.Gabbrath = "Reverberation"
defaults.chain_by_mob.Cehuetzi = "Fusion"
defaults.chain_by_mob.Waktza = "Gravitation"

defaults.chain_spells = {}
defaults.chain_spells.Earth = {normal="Stone", helix="Geohelix"}
defaults.chain_spells.Water = {normal="Water", helix="Hydrohelix"}
defaults.chain_spells.Wind = {normal="Aero", helix="Anemohelix"}
defaults.chain_spells.Fire = {normal="Fire", helix="Pyrohelix"}
defaults.chain_spells.Ice = {normal="Blizzard", helix="Cryohelix"}
defaults.chain_spells.Lightning = {normal="Thunder", helix="Ionohelix"}
defaults.chain_spells.Dark = {normal="Noctohelix", helix="Noctohelix"}
defaults.chain_spells.Light = {normal="Luminohelix", helix="Luminohelix"}

settings = config.load(defaults)

last_ws = {}

windower.register_event("addon command", function (...)
    local params = {...}

    for i,v in pairs(params) do params[i]=windower.convert_auto_trans(params[i]):lower() end
    for i,v in pairs(params) do params[i]=params[i]:lower() end

    local skillchain_name = 'auto'

    if #params == 1 then
	    if params[1] == "helix" then
	    	settings.IO.default_helix = not settings.IO.default_helix
	    	settings:save()
	    	feedback("Using Helix closers: "..tostring(settings.IO.default_helix), 0)
	    	return
	    elseif params[1] == "fallback" then
	    	settings.IO.allow_helix_recast_fallback = not settings.IO.allow_helix_recast_fallback
	    	settings:save()
	    	feedback("Using alternatives when Helix unavailable: "..tostring(settings.IO.allow_helix_recast_fallback), 0)
	    	return
	    elseif params[1] == "status" then
	    	for item,value in pairs(settings.IO) do
	    		feedback(item..": "..tostring(value), 0)
	    	end
	    	return
	    --elseif settings.skillchains[firstToUpper(params[1])] ~= nil then --Match exact chain first
	    	--skillchain_name = firstToUpper(params[1])
	    elseif params[1] == "lf" or params[1] == "3step" then --Shortcuts for 3step Liqfusion
	    	skillchain_name = "Liqfusion"
	    else --Fuzzy Match for a chain
	    	skillchain_name = fmatch(params[1], keys(settings.skillchains))
	    end
	elseif #params == 2 then
		if params[1] == "verbosity" then
			local param_2_numeric = tonumber(params[2], 10)
			if param_2_numeric then
				if param_2_numeric <= 2 and param_2_numeric >= 0 then
					settings.IO.verbosity = param_2_numeric
					settings:save()
					feedback("Verbosity set to: "..settings.IO.verbosity, 0)
				else
					feedback("Verbosity values are 0, 1, or 2", 0)
				end
			end
			return
		elseif params[1] == "feedback" then
			if T{'console', 'chat'}:contains(params[2]) then
				settings.IO.feedback_channel = params[2]
				settings:save()
				feedback("Feedback channel set to: "..settings.IO.feedback_channel, 0)
			else
				feedback("Feedback channel values are 'console' or 'chat'", 0)
			end
			return
		elseif params[1] == "announce" then
			if T{'linkshell', 'linkshell2', 'party', 'say', 'echo', 'l', 'l2', 'p', 's', 'none'}:contains(params[2]) then
				settings.IO.announce_channel = params[2]
				settings:save()
				feedback("Annouce channel set to: "..settings.IO.announce_channel, 0)
			else
				feedback("Annouce channel values are linkshell, linkshell2, party, say, echo, or none", 0)				
			end
			return
		elseif params[1] == "default" then
			settings.IO.default_chain = fmatch(params[2], keys(settings.skillchains))
			settings:save()
			feedback("Default chain set to: "..settings.IO.default_chain, 0)
			return
		end
	end

	make_skillchain(skillchain_name)
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
	if act['category'] == 11 then
		if res.monster_abilities[act['param']] then
			last_ws[windower.ffxi.get_mob_by_id(act['actor_id'])['index']] = res.monster_abilities[act['param']]['en']
		end
	end
end)

windower.register_event('zone change', function(new_id, old_id)
	--Reset last WS history
	last_ws = {}
end)

function keys(tab)
	local keyset=T{}
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
		['Undulating Shockwave'] = 'Induration', --Shockwave is a Thunder-mode WS, but causes the switch to wind mode

		['Flaming Kick'] = 'Reverberation',
		--['Flaming Kick'] = 'Distortion', --Helix opener is slower, and D/H are never weak to ice to get lucky on element swap during SC

		--['Icy Grasp'] = 'Liquefaction',
		--['Icy Grasp'] = 'Fusion',
		['Icy Grasp'] = 'Liqfusion',

		['Zap'] = 'Scission',
		['Concussive Shock'] = 'Scission',
		['Shrieking Gale'] = 'Scission', --Gale is a Wind-mode WS, but causes the switch to thunder mode

		--['Fulminous Smash'] = 'Scission',
		['Fulminous Smash'] = 'Gravitation'
	}

	return elemental_ws_to_sc[last_ws[index]] or "You haven't seen "..windower.get_mob_by_index(index)['name'].." use a WS yet, no auto-chain available"
end

function firstToUpper(str)
    return (str:gsub("^%l", string.upper))
end

function make_skillchain(chain_name)
	local player = windower.ffxi.get_player()

	if player['target_index'] == nil then
		feedback("No target", 1)
		return
	end
	if player['main_job'] ~= "SCH" then
		feedback("You're not on SCH", 0)
		return
	end

	local target_name_no_spaces = windower.ffxi.get_mob_by_index(player['target_index'])['name']:gsub("%s+", "")
	local buffs = T(player['buffs'])
	local abil_recasts = T(windower.ffxi.get_ability_recasts())
	local spell_recasts = T(windower.ffxi.get_spell_recasts())

	--Don't MPK tanks
	if S{'Leshonn','Gartell','HaughtyTulittia'}:contains(target_name_no_spaces) then
		use_helix = false
	else
		use_helix = settings.IO.default_helix
	end

	if chain_name == 'auto' then
		if settings.chain_by_mob[target_name_no_spaces] ~= nil then
			chain_name = settings.chain_by_mob[target_name_no_spaces]
		elseif S{'Leshonn','Degei','Gartell','Aita'}:contains(target_name_no_spaces) then
			chain_name = bdgh_skillchain(player['target_index'])
		else
			chain_name = settings.IO.default_chain
		end
	end

	--Account for immanence already existing
	local active_immanence = 0
	if buffs:contains(res.buffs:with('en', "Immanence")['id']) then
		active_immanence = 33
	end

	if settings.skillchains[chain_name] ~= nil then
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
			local skillchain_steps = split_trim(settings.skillchains[chain_name], ",")
			for step,element in ipairs(skillchain_steps) do

				if abil_recasts[res.ability_recasts:with('en', 'Stratagems')['id']] < active_immanence+33*(5-step)+execution_time then
					command_list[#command_list+1] = "Immanence"
					execution_time = execution_time + settings.wait.post_ja
				else
					failure_reason = "Unable to use Immanence #"..step
					break
				end

				if step == 1 or not use_helix then
					spell = settings.chain_spells[element]['normal']
				else
					spell = settings.chain_spells[element]['helix']
					if spell_recasts[res.spells:with('en', spell)['id']]/60 > execution_time and settings.IO.allow_helix_recast_fallback then
						spell = settings.chain_spells[element]['normal']
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
			feedback(failure_reason, 1)
		else
			run_commands(command_list, 1, chain_name, os.clock())
		end
	else
		feedback(chain_name.." is not a valid chain", 1)
	end
end

function run_commands(command_list, command_index, chain_name, start_time)
	if command_index <= #command_list then
		local current_command = command_list[command_index]
		local player = windower.ffxi.get_player()

		local buffs = T(windower.ffxi.get_player()['buffs'])
		local blocking_status = T{'KO','sleep','paralysis','petrification','stun','charm','amnesia','terror','Lullaby','encumbrance','silence','mute'}
		
		for _,v in pairs(blocking_status) do
			if buffs:contains(res.buffs:with('en', v)['id']) then
				feedback("Chain: Stopping execution for status "..v, 1)
				return
			end
		end

		if player['target_index'] == nil then
			feedback("Chain: Stopping execution, no target", 1)
			return
		end

		if buffs:contains(res.buffs:with('en', "Immanence")['id']) and current_command == "Immanence" and command_index <= 2 then
			--Already had immanence up, skip to next action. 
			--Only valid for the first Imma, others might be buffs updating slow.
			run_commands(command_list,command_index+1, chain_name, start_time)
		else
			windower.send_command(current_command)
			feedback(current_command.."@t="..math.round(os.clock()-start_time, 1), 2)

			if T{'Immanence','DarkArts'}:contains(current_command) then
				coroutine.sleep(settings.wait.post_ja)
			else
				if announce_channel ~= 'none' then
					if command_index <= 3 then --da-imma-OPENER or imma-OPENER-imma
						windower.send_command("input /"..settings.IO.announce_channel.." Opening "..chain_name..": "..current_command)
					else
						windower.send_command("input /"..settings.IO.announce_channel.." "..chain_name..": "..current_command)
					end
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

			run_commands(command_list,command_index+1, chain_name, start_time)
		end
	end
end

function feedback(message, priority)
	if settings.IO.verbosity >= priority then
		if settings.IO.feedback_channel == "console" then
			print(message)
		elseif settings.IO.feedback_channel == "chat" then
			windower.add_to_chat(207, message)
		end
	end
end

function split_trim (inputstr, sep)
    if sep == nil then
            sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    		str = str:gsub("%s+", "")
            table.insert(t, str)
    end
    return t
end