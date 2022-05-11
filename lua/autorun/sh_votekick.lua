--[[------------------------------------------------------------------
	Simple Votekick
	Version 2
	May 11th, 2022
	Made by DyaMetR
]]--------------------------------------------------------------------

-- addon information
local NAME = 'Simple Votekick'
local VERSION = '2'

-- network strings
local NET = 'simple_votekick'
local NET_END = NET .. '_end'
local NET_VOTE = NET .. '_vote'
local NET_NOTIFY = NET .. '_notify'

-- RESULT_ enum
local RESULT_ABORT = 0
local RESULT_SUCCESS = 1
local RESULT_FAILURE = 2
local RESULT_INSUFFICIENT = 3

-- network socket size for integers
local NUMBER_SIZE = 16
local TYPE_SIZE = 4

-- commands
local COMMAND_PREFIX = '!'
local COMMAND_YES = COMMAND_PREFIX .. 'yes'
local COMMAND_NO = COMMAND_PREFIX .. 'no'
local COMMAND_MENU = COMMAND_PREFIX .. 'votekick'

-- console commands
local CONCOMMAND_MENU = 'votekick_menu'

if SERVER then

	-- register network string
	util.AddNetworkString(NET)
	util.AddNetworkString(NET_END)
	util.AddNetworkString(NET_VOTE)
	util.AddNetworkString(NET_NOTIFY)

	-- locale
	local MESSAGE_KICKED = 'You\'ve been voted off'
	local MESSAGE_BAN_TIME = MESSAGE_KICKED .. '. Come back in %s minutes'
	local MESSAGE_REJOIN = 'You\'ve been recently voted off and still have to wait for %s minutes'
	local PRINT_ALREADY = 'A vote is already running!'
	local PRINT_COOLDOWN = 'You have to wait for another %s minutes before starting another vote.'
	local PRINT_MINPLAYERS = 'There has to be at least %s players in the server for a vote to be started!'
	local PRINT_EMPTY = 'You need to specify a reason!'
	local PRINT_ABORT = 'An administrator cancelled the current vote!'
	local PRINT_ANTIABUSE = 'Unable to abort current vote as you\'re the target. Enable administrator immunity to avoid being voted off.'
	local LOG_VOTE = '%s (%s) started a vote to kick %s (%s) for the reason: %s'

	-- register console variables
	local ENABLED = CreateConVar('sv_votekick', 1, { FCVAR_ARCHIVE, FCVAR_NOTIFY }, 'Enables Simple Votekick System.')
	local ADMIN = CreateConVar('sv_votekick_immuneadmins', 1, { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }, 'Doesn\'t allow players to kick administrators.')
	local BAN_TIME = CreateConVar('sv_votekick_bantime', 5, { FCVAR_ARCHIVE, FCVAR_NOTIFY }, 'Minutes a player will remain banned after being kicked. "0" will yield no cooldown.')
	local VOTE_TIME = CreateConVar('sv_votekick_votetime', 30, { FCVAR_ARCHIVE, FCVAR_NOTIFY }, 'How many seconds does voting lasts for.')
	local COOLDOWN = CreateConVar('sv_votekick_cooldown', 5, { FCVAR_ARCHIVE, FCVAR_NOTIFY }, 'Minutes a player will have to wait before being able to start a vote again.')
	local MIN_VOTE = CreateConVar('sv_votekick_minvotes', 50, { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED }, 'Minimum percentage of players to vote for the voting to be valid.')
	local MIN_PLAYERS = CreateConVar('sv_votekick_minplayers', 4, { FCVAR_ARCHIVE, FCVAR_NOTIFY }, 'Minimum amount of players required to start a vote.')

	-- timer names
	local TIMER = 'votekick'
	local TIMER_BAN = TIMER .. '_ban_%s'
	local TIMER_COOLDOWN = TIMER .. '_cooldown_%s'

	-- notify types
	local NOTIFY_GENERIC, NOTIFY_ERROR, NOTIFY_UNDO, NOTIFY_HINT, NOTIFY_CLEANUP = 0, 1, 2, 3, 4

	-- variables
	local cooldown = {} -- players in voting cooldown
	local banned = {} -- players currently banned
	local vote = { -- current vote status
		voters = {},
		yes = 0,
		no = 0,
		time = 0,
		active = false
	}

	--[[------------------------------------------------------------------
		Whether the given Steam ID is currently banned.
		@param {string} Steam ID
		@return {boolean} is player banned
	]]--------------------------------------------------------------------
	local function isBanned(steamid)
		return banned[steamid] and banned[steamid] > os.time()
	end

	--[[------------------------------------------------------------------
		Returns the maximum amount of voters currently available.
		@return {number} maximum voters
	]]--------------------------------------------------------------------
	local function getMaxVoters()
		return player.GetCount() - 2
	end

	--[[------------------------------------------------------------------
		Sends a notification to a player.
		@param {Player} player
		@param {string} message
		@param {number} duration of the notification
	]]--------------------------------------------------------------------
	local function notify(_player, message, _type, length)
		net.Start(NET_NOTIFY)
		net.WriteString(message)
		net.WriteInt(_type, TYPE_SIZE)
		net.WriteFloat(length)
		net.Send(_player)
	end

	--[[------------------------------------------------------------------
		Applies a ban to the given Steam ID and returns how long will the player be banned for.
		@param {Player} player
	]]--------------------------------------------------------------------
	local function ban(steamid)
		local seconds = BAN_TIME:GetFloat() * 60

		-- register ban
		banned[steamid] = os.time() + seconds

		-- after the given amount of time passes, remove player from the list
		timer.Create(string.format(TIMER_BAN, steamid), seconds, 1, function()
			banned[steamid] = nil
		end)
	end

	--[[------------------------------------------------------------------
		Kicks a player and registers them in the banned list.
		@param {Player} player
	]]--------------------------------------------------------------------
	local function kick(_player)
		ban(_player:SteamID())
		_player:Kick(string.format(MESSAGE_BAN_TIME, math.ceil(BAN_TIME:GetFloat())))
	end

	--[[------------------------------------------------------------------
		Applies a voting cooldown to a player.
		@param {Player} player
	]]--------------------------------------------------------------------
	local function applyCooldown(_player)
		local time, steamid = COOLDOWN:GetFloat() * 60, _player:SteamID()

		-- register cooldown
		cooldown[steamid] = os.time() + time

		-- after the given amount of time passes, remove player from the list
		timer.Create(string.format(TIMER_COOLDOWN, steamid), time, 1, function()
			cooldown[steamid] = nil
		end)
	end

	--[[------------------------------------------------------------------
		Halts the current vote and prompts the players about the veredict.
		@param {RESULT_} reason for the vote to be halted
	]]--------------------------------------------------------------------
	function halt(reason)
		timer.Remove(TIMER) -- remove timer in case it's still running

		-- reset voting data
		table.Empty(vote.voters)
		vote.active = false
		vote.yes = 0
		vote.no = 0
		vote.time = 0
		vote.kicker = nil
		vote.kickerId = nil
		vote.kicked = nil
		vote.reason = nil

		-- notify clients about the result
		net.Start(NET_END)
		net.WriteInt(reason, NUMBER_SIZE)
		net.Broadcast()
	end

	--[[------------------------------------------------------------------
		Finishes the current vote.
	]]--------------------------------------------------------------------
	local function finish()
		local voters = getMaxVoters()

		-- check if enough players participated in the voting
		if table.Count(vote.voters) >= math.ceil(voters * MIN_VOTE:GetInt() * .01) then
			-- check if enough players voted 'Yes'
			if vote.yes > vote.no then
				kick(vote.kicked)
				halt(RESULT_SUCCESS)
			else
				halt(RESULT_FAILURE)
			end
		else
			halt(RESULT_INSUFFICIENT)
		end
	end

	--[[------------------------------------------------------------------
		Starts a kicking vote.
		@param {Player} player starting the vote
		@param {Player} player threatened to be kicked
		@param {string} reason to be kicked
	]]--------------------------------------------------------------------
	local function start(kicker, kicked, reason)
		if not ENABLED:GetBool() or not reason or (ADMIN:GetBool() and kicked:IsAdmin()) or kicker == kicked then return end

		-- ignore attempt if the reason is empty
		if string.len(string.Trim(reason)) <= 0 then
			notify(kicker, PRINT_EMPTY, NOTIFY_ERROR, 4)
			return
		end

		-- do not allow new votes if there aren't enough players
		local minplayers = MIN_PLAYERS:GetInt()
		if player.GetCount() < minplayers then
			notify(kicker, string.format(PRINT_MINPLAYERS, minplayers), NOTIFY_HINT, 4)
			return
		end

		-- do not allow new votes when one is already running
		if vote.active then
			notify(kicker, PRINT_ALREADY, NOTIFY_ERROR, 4)
			return
		end

		-- do not allow new votes if this player already casted one
		local _cooldown, current = cooldown[kicker:SteamID()], os.time()
		if _cooldown and _cooldown > current then
			notify(kicker, string.format(PRINT_COOLDOWN, math.ceil((_cooldown - current) / 60)), NOTIFY_UNDO, 4)
			return
		end

		local time = VOTE_TIME:GetFloat()
		local voteEnd = CurTime() + time

		applyCooldown(kicker) -- apply cooldown

		-- send voting information to clients
		net.Start(NET)
		net.WriteString(kicker:Name())
		net.WriteString(kicked:Name())
		net.WriteString(reason)
		net.WriteFloat(voteEnd)
		net.WriteInt(0, NUMBER_SIZE)
		net.WriteInt(0, NUMBER_SIZE)
		net.WriteInt(0, NUMBER_SIZE)
		net.Broadcast()

		-- register information
		vote.time = voteEnd
		vote.kicker = kicker
		vote.kickerId = kicker:SteamID()
		vote.kicked = kicked
		vote.reason = reason
		vote.active = true

		-- create timer
		timer.Create(TIMER, time, 1, finish)

		-- log attempt
		print(string.format(LOG_VOTE, kicker:Name(), kicker:SteamID(), kicked:Name(), kicked:SteamID(), reason))
	end

	--[[------------------------------------------------------------------
		Votes on the current vote.
		@param {Player} voter
		@param {boolean} was it a positive vote
	]]--------------------------------------------------------------------
	local function doVote(voter, yes)
		if not vote.active or vote.voters[voter] ~= nil or vote.kicker == voter or vote.kicked == voter then return end
		vote.voters[voter] = yes -- register voter

		-- register vote type
		if yes then
			vote.yes = vote.yes + 1
		else
			vote.no = vote.no + 1
		end

		-- send to all players
		net.Start(NET_VOTE)
		net.WriteBool(yes)
		net.WriteBool(true)
		net.Broadcast()

		-- if enough players voted, finish prematurely the voting
		if table.Count(vote.voters) >= getMaxVoters() then
			finish()
		end
	end

	--[[------------------------------------------------------------------
		Manages the chat commands.
	]]--------------------------------------------------------------------
	hook.Add('PlayerSay', NET, function(sender, text, _)
		text = string.Trim(text) -- trim text
		if string.sub(text, 1, 1) ~= COMMAND_PREFIX then return end -- if there's no prefix, ignore
		if text == COMMAND_YES then
			doVote(sender, true)
			return false
		elseif text == COMMAND_NO then
			doVote(sender, false)
			return false
		elseif text == COMMAND_MENU then
			sender:ConCommand(CONCOMMAND_MENU)
			return false
		end
	end)

	--[[------------------------------------------------------------------
		Kicks back players if they're banned.
	]]--------------------------------------------------------------------
	hook.Add('PlayerAuthed', NET, function(_player, steamid, uniqueid)
		if not ENABLED:GetBool() or not isBanned(steamid) then return end
		_player:Kick(string.format(MESSAGE_REJOIN, math.ceil((banned[steamid] - os.time()) / 60)))
	end)

	--[[------------------------------------------------------------------
		Notifies players that the server they joined is running the addon.
	]]--------------------------------------------------------------------
	hook.Add('PlayerInitialSpawn', NET, function(_player)
		if not ENABLED:GetBool() or not vote.active then return end

		-- check if the player started the current vote
		if vote.kickerId == _player:SteamID() then
			vote.kicker = _player
		end

		-- if the player joins during a vote, send it
		net.Start(NET)
		net.WriteString(vote.kicker:Name())
		net.WriteString(vote.kicked:Name())
		net.WriteString(vote.reason)
		net.WriteFloat(vote.time)
		net.WriteInt(table.Count(vote.voter), NUMBER_SIZE)
		net.WriteInt(vote.yes, NUMBER_SIZE)
		net.WriteInt(vote.no, NUMBER_SIZE)
		net.Send(_player)
	end)

	--[[------------------------------------------------------------------
		End vote if all players but this one voted. Or automatically kick if it's a ban evasion.
	]]--------------------------------------------------------------------
	hook.Add('PlayerDisconnected', NET, function(_player)
		if not ENABLED:GetBool() or not vote.active then return end

		-- if it's a ban evasion, apply ban
		if vote.kicked == _player then
			halt(RESULT_SUCCESS)
			ban(_player:SteamID())
		else
			-- remove vote
			local voted = vote.voters[_player]
			if voted ~= nil then
				vote.voters[_player] = nil

				-- send reverted vote
				net.Start(NET_VOTE)
				net.WriteBool(voted)
				net.WriteBool(false)
				net.Broadcast()
			end

			-- check if the voters left are enough to finish the vote
			if table.Count(vote.voters) >= getMaxVoters() then
				finish()
			end
		end
	end)

	--[[------------------------------------------------------------------
		If the addon is disabled during a vote, it cancels it.
	]]--------------------------------------------------------------------
	cvars.AddChangeCallback(ENABLED:GetName(), function(_, _, new)
		local value = tonumber(new)
		if value and value ~= 0 then return end
		halt(RESULT_ABORT)
	end, NET)

	--[[------------------------------------------------------------------
		Receive new vote.
	]]--------------------------------------------------------------------
	net.Receive(NET, function(len, _player)
		local kicked = net.ReadEntity()
		local reason = net.ReadString()

		if not IsValid(_player) or not IsValid(kicked) then return end

		start(_player, kicked, reason)
	end)

	--[[------------------------------------------------------------------
		Allow admins to abort a vote to avoid abuse.
	]]--------------------------------------------------------------------
	concommand.Add('votekick_abort', function(admin)
		if not vote.active or not admin:IsAdmin() then return end

		-- avoid abusive admins from cancelling votes
		if not ADMIN:GetBool() and admin == vote.kicked then
			notify(admin, PRINT_ANTIABUSE, NOTIFY_ERROR, 8)
			return
		end

		-- halt current vote
		halt(RESULT_ABORT)

		-- notify all players that an admin aborted the current vote
		for _, _player in pairs(player.GetAll()) do
			notify(_player, PRINT_ABORT, NOTIFY_CLEANUP, 6)
		end
	end)

end

if CLIENT then

	local INVALID_STRING = 'NULL'
	local CHAT_CONCOMMAND = 'say'
	local PLACEHOLDER = '%s'

	-- hooks
	local HOOK_DRAW = 'VotekickHUDPaint'
	local HOOK_SOUND_START = 'VotekickBeginSound'
	local HOOK_SOUND_VOTE = 'VotekickVoteSound'
	local HOOK_SOUND_SUCCESS = 'VotekickSuccessSound'
	local HOOK_SOUND_FAILURE = 'VotekickFailSound'
	local HOOK_SOUND_ABORT = 'VotekickAbortSound'

	-- sizes and offsets
	local BORDER_SIZE, MARGIN = 6, 32
	local X, Y, W, H = 36, 27, 320, 130
	local SEG_W, SEG_H, SEG_MARGIN = 13, 8, 7

	-- fonts
	local FONT_NUMBER = NET .. '_number'
	local FONT_SCANLINES = NET .. '_scanlines'
	local FONT_LARGE = NET .. '_large'
	local FONT_SMALL = NET .. '_small'
	local FONT_HINT = NET .. '_hint'

	-- animations
	local BLINK_SPEED = 1.5
	local SCANLINES_IN_SPEED, SCANLINES_OUT_SPEED = 6, .8
	local NUMBER_YES, NUMBER_NO = 1, 2

	-- colours
	local COLOUR_BACKGROUND = Color(0, 0, 0, 66)
	local COLOUR_TINT = Color(255, 230, 0)
	local COLOUR_POSITIVE = Color(88, 255, 66)
	local COLOUR_NEGATIVE = Color(255, 33, 0)
	local COLOUR_SEGMENT = Color(0, 0, 0, 80)
	local COLOUR_HOSTNAME = Color(133, 193, 255)
	local COLOUR_NAME = Color(255, 180, 66)
	local COLOUR_COMMAND = Color(213, 30, 30)
	local COLOUR_BASE = Color(222, 222, 222)

	-- menu
	local MENU_FONT = NET .. '_menu'
	local MENU_BACKGROUND, MENU_IDLE = Color(33, 33, 33), Color(200, 200, 200)
	local MENU_SELECTED = Color(226, 51, 27)

	-- create menu font
	surface.CreateFont(MENU_FONT, {
		font = 'Tahoma',
		size = 18,
		weight = 1000
	})

	-- sounds
	local SOUND_START = 'common/warning.wav'
	local SOUND_SUCCESS = 'buttons/button14.wav'
	local SOUND_FAILURE = 'buttons/button19.wav'
	local SOUND_ABORT = 'common/wpn_denyselect.wav'
	local NOTIFY_SOUNDS = {
		'buttons/lightswitch2.wav',
		'buttons/button10.wav',
		'buttons/button9.wav',
		'ambient/water/drip2.wav',
		'buttons/button15.wav'
	}

	-- locale
	local MESSAGE_WELCOME = '%s is running %s version %s. Open the menu by typing %s on the chat!'
	local HUD_SUCCESS = 'SUCCESS! KICKING %s...'
	local HUD_FAILURE = 'NOT ENOUGH PEOPLE VOTED \'YES\''
	local HUD_INSUFFICIENT = 'INSUFFICIENT PARTICIPATION'
	local HUD_KICKER = '%s CALLED A VOTE'
	local HUD_KICKED = 'KICK %s?'
	local HUD_REASON = '(%s)'
	local HUD_INSTRUCTIONS = 'TO VOTE, TYPE IN CHAT:'
	local MENU_TITLE = 'Select a player to kick'
	local MENU_REASON_TITLE, MENU_REASON = 'Provide a reason', 'Why would you like %s to be kicked?'
	local MENU_DISCONNECTED_TITLE, MENU_DISCONNECTED = 'Disconnected player', 'This player has disconnected. You cannot vote them off.'

	-- register console variables
	local KEYS = CreateClientConVar('cl_votekick_usebinds', 1, true, false, 'Use a key to vote instead of strictly console commands.')
	local KEY_YES = CreateClientConVar('cl_votekick_bind_yes', KEY_F7)
	local KEY_NO = CreateClientConVar('cl_votekick_bind_no', KEY_F8)
	local MIN_VOTE = CreateClientConVar('sv_votekick_minvotes', 50, false, false, 'Minimum percentage of players to vote for the voting to be valid.')
	local ADMIN = CreateClientConVar('sv_votekick_immuneadmins', 1, false, false, 'Doesn\'t allow players to kick administrators.')

	local POST_VOTE_DISPLAY_TIME = 5 -- for how long is the result shown before vanishing

	-- variables
	local blink, blinkColour = 0, COLOUR_TINT
	local numbers = {}
	local vote = { -- current vote status
		yes = 0,
		no = 0,
		time = 0,
		active = false,
		result = { -- vote result data
			display = 0,
			result = false
		}
	}

	--[[------------------------------------------------------------------
		Returns the HUD elements' scale.
		@return {number} scale
	]]--------------------------------------------------------------------
	local function getScale()
		return ScrH() / 1080
	end

	--[[------------------------------------------------------------------
		Creates all fonts with the adequeate scale.
	]]--------------------------------------------------------------------
	local function createFonts()
		local scale = getScale()

		-- number font
		surface.CreateFont(FONT_NUMBER, {
			font = 'HalfLife2',
			size = 56 * scale,
			additive = true
		})

		-- number scanline font
		surface.CreateFont(FONT_SCANLINES, {
			font = 'HalfLife2',
			size = 56 * scale,
			additive = true,
			scanlines = 3,
			blursize = 8
		})

		-- large font
		surface.CreateFont(FONT_LARGE, {
			font = 'Tahoma',
			size = 26 * scale,
			weight = 800
		})

		-- small font
		surface.CreateFont(FONT_SMALL, {
			font = 'Verdana',
			size = 20 * scale,
			weight = 800
		})

		-- tiny font
		surface.CreateFont(FONT_HINT, {
			font = 'Tahoma',
			size = 15 * scale,
			weight = 1000
		})
	end

	--[[------------------------------------------------------------------
		Draws an animable number.
		@param {string} identifier
	]]--------------------------------------------------------------------
	local function addNumber(id)
		numbers[id] = { blinked = true, amount = 0, value = 0 }
	end

	--[[------------------------------------------------------------------
		Sets a number's value, making it blink if it's different.
		@param {string} identifier
	]]--------------------------------------------------------------------
	local function setNumber(id, value)
		if numbers[id].value == value then return end
		numbers[id].value = value
		numbers[id].blinked = false
	end

	--[[------------------------------------------------------------------
		Draws a number with scanlines.
		@param {number} x
		@param {number} y
		@param {number} amount
		@param {Color} colour
		@param {TEXT_ALIGN_} text alignment
		@param {number|nil} scalines amount
	]]--------------------------------------------------------------------
	local function drawNumber(x, y, amount, colour, align, scanlines)
		draw.SimpleText(amount, FONT_NUMBER, x, y, colour, align)
		if not scanlines then return end
		surface.SetAlphaMultiplier(scanlines)
		draw.SimpleText(amount, FONT_SCANLINES, x, y, colour, align)
		surface.SetAlphaMultiplier(1)
	end

	--[[------------------------------------------------------------------
		Calls the given hook, and if it's not replaced, plays the default sound.
		@param {string} default sound
		@param {string} hook
	]]--------------------------------------------------------------------
	local function playSound(default, _hook)
		if hook.Run(_hook) then return end
		surface.PlaySound(default)
	end

	--[[------------------------------------------------------------------
		Draws the voting UI frame.
		@param {number} x
		@param {number} y
		@param {number} width
		@param {number} height
		@param {number|nil} blink amount
		@param {Color|nil} blinking colour
		@param {string|nil} vote starter's name
		@param {string|nil} vote target's name
		@param {string|nil} reason to kick
		@param {number|nil} seconds left to vote
		@return {number} final x position
		@return {number} final scaled width
	]]--------------------------------------------------------------------
	local function drawFrame(x, y, w, h, scale, blink, blinkColour, kicker, kicked, reason, time)
		kicker = string.format(HUD_KICKER, kicker or INVALID_STRING)
		kicked = string.format(HUD_KICKED, kicked or INVALID_STRING)
		reason = string.format(HUD_REASON, string.upper(reason or INVALID_STRING))

		-- get scaled size
		local _w, _h, margin = w * scale, h * scale, (MARGIN + X * 2) * scale

		-- resize if either strings are too long
		surface.SetFont(FONT_SMALL)
		_w = math.max(_w, surface.GetTextSize(kicker) + margin)
		_w = math.max(_w, surface.GetTextSize(reason) + margin)
		surface.SetFont(FONT_LARGE)
		_w = math.max(_w, surface.GetTextSize(kicked) + margin)

		-- apply right side alignment
		x = x - _w

		-- draw background
		draw.RoundedBox(BORDER_SIZE, x, y, _w, _h, COLOUR_BACKGROUND)

		-- draw blinking
		if blink then
			surface.SetAlphaMultiplier(blink)
			draw.RoundedBox(BORDER_SIZE, x, y, _w, _h, blinkColour)
			surface.SetAlphaMultiplier(1)
		end

		-- draw vote information
		draw.SimpleText(kicker, FONT_SMALL, x + 20 * scale, y + 15 * scale, COLOUR_TINT)
		draw.SimpleText(kicked, FONT_LARGE, x + 20 * scale, y + 38 * scale, COLOUR_TINT)
		draw.SimpleText(reason, FONT_SMALL, x + 20 * scale, y + 66 * scale, COLOUR_TINT)

		-- draw time if provided
		if time then draw.SimpleText(math.max(time, 0), FONT_SMALL, x + _w - 20 * scale, y + 15 * scale, COLOUR_TINT, TEXT_ALIGN_RIGHT) end

		return x, _w
	end

	--[[------------------------------------------------------------------
		Draws the voting UI frame.
		@param {number} x
		@param {number} y
		@param {number} width
		@param {number} height
		@param {number|nil} blink amount
		@param {Color|nil} blinking colour
		@param {string|nil} vote starter's name
		@param {string|nil} vote target's name
		@param {string|nil} reason to kick
		@param {string|nil} veredict
		@param {Color|nil} veredict colour
	]]--------------------------------------------------------------------
	local function drawVeredict(x, y, w, h, scale, blink, blinkColour, kicker, kicked, reason, veredict, colour)
		surface.SetFont(FONT_LARGE)
		x = drawFrame(x, y, math.max(w, math.ceil(surface.GetTextSize(veredict) / scale) + 40), h, scale, blink, blinkColour, kicker, kicked, reason)
		draw.SimpleText(veredict or INVALID_STRING, FONT_LARGE, x + 20 * scale, y + 92 * scale, colour)
	end

	--[[------------------------------------------------------------------
		Draws the voting UI frame.
		@param {number} x
		@param {number} y
		@param {number} width
		@param {number} height
		@param {number|nil} blink amount
		@param {Color|nil} blinking colour
		@param {string|nil} vote starter's name
		@param {string|nil} vote target's name
		@param {string|nil} reason to kick
		@param {number|nil} seconds left to vote
		@param {number|nil} yes votes
		@param {number|nil} no votes
		@param {number|nil} yes votes counter animation progress
		@param {number|nil} no votes counter animation progress
	]]--------------------------------------------------------------------
	local function drawStatus(x, y, w, h, scale, blink, blinkColour, kicker, kicked, reason, time, yes, no, yesAnim, noAnim)
		yes = yes or 0
		no = no or 0

		-- make it taller if we're not using binds
		local usingBinds = KEYS:GetBool()
		if not usingBinds then h = h + 20 end

		-- get scaled size
		local _h, _w = h * scale

		-- draw background
		x, _w = drawFrame(x, y, w, h, scale, blink, blinkColour, kicker, kicked, reason, time)

		-- draw voting status
		drawNumber(x + 20 * scale, y + 84 * scale, yes, COLOUR_POSITIVE, nil, yesAnim)
		drawNumber(x + _w - 20 * scale, y + 84 * scale, no, COLOUR_NEGATIVE, TEXT_ALIGN_RIGHT, noAnim)

		-- get bar data
		local players, votes = player.GetCount() - 2, yes + no
		local minVotes = math.ceil(players * MIN_VOTE:GetFloat() * .01) -- minimum amount of players needed to vote
		local yesFrac, noFrac = yes / math.max(votes, minVotes), no / math.max(votes, minVotes)

		-- get segments size
		local segment = (SEG_W * scale) + (SEG_MARGIN * scale) -- full segment size (with margin)
		local segments = ((_w - 40 * scale) / segment) - 1 -- how many segments fit
		local margin = x + (_w * .5) - (segments * segment * .5) - (SEG_MARGIN * scale) -- segment chain horizontal offset

		-- draw segment bar
		for i=0, segments do
			local frac, colour = i/segments, COLOUR_SEGMENT

			-- choose segment colour
			if yes > 0 and frac <= yesFrac then
				colour = COLOUR_POSITIVE
			elseif no > 0 and 1 - frac <= noFrac then
				colour = COLOUR_NEGATIVE
			end

			-- draw segment
			draw.RoundedBox(0, margin + (segment * i), y + 142 * scale, SEG_W * scale, SEG_H * scale, colour)
		end

		-- lower binds and add instructions if we're not using hints
		local yes_hint, no_hint = string.upper(input.GetKeyName(KEY_YES:GetInt())), string.upper(input.GetKeyName(KEY_NO:GetInt()))
		if not usingBinds then
			yes_hint = COMMAND_YES
			no_hint = COMMAND_NO
			draw.SimpleText(HUD_INSTRUCTIONS, FONT_HINT, x + 20 * scale, y + _h - 38 * scale, COLOUR_TINT, nil, TEXT_ALIGN_BOTTOM)
		end

		-- draw instructions
		draw.SimpleText(yes_hint, FONT_SMALL, x + 20 * scale, y + _h - 16 * scale, COLOUR_TINT, nil, TEXT_ALIGN_BOTTOM)
		draw.SimpleText(no_hint, FONT_SMALL, x + _w - 20 * scale, y + _h - 16 * scale, COLOUR_TINT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end

	--[[------------------------------------------------------------------
		Creates the voting menu.
	]]--------------------------------------------------------------------
	local function menu()
		local resolution = 128
		local w, h = ScrW() * .66, ScrH() * .8

		-- create frame
		local frame = vgui.Create('DFrame')
		frame:ShowCloseButton(true)
		frame:SetTitle(MENU_TITLE)
		frame:SetSize(w, h)
		frame:Center()
		frame:MakePopup()

		-- create scrolling panel
		local scroll = vgui.Create('DScrollPanel', frame)
		scroll:Dock(FILL)

		-- create list
		local list = vgui.Create('DIconLayout', scroll)
		list:Dock(FILL)
		list:SetSpaceX(5)
		list:SetSpaceY(5)

		-- populate list
		for _, _player in pairs(player.GetAll()) do
			if _player == LocalPlayer() or (ADMIN:GetBool() and _player:IsAdmin()) then continue end

			-- create background
			local panel = vgui.Create('DPanel')
			panel:SetSize(resolution, resolution + 24)
			panel:SetBackgroundColor(MENU_BACKGROUND)

			-- add avatar
			local avatar = vgui.Create('AvatarImage', panel)
			avatar:SetSize(resolution, resolution)
			avatar:SetPlayer(_player, resolution)

			-- add name
			local name = vgui.Create('DLabel', panel)
			name:SetFont(MENU_FONT)
			name:SetTextColor(MENU_IDLE)
			name:SetText(_player:Name())
			name:SizeToContents()
			name:SetPos((avatar:GetWide() * .5) - name:GetWide() * .5, avatar:GetTall() + 2)

			-- create button
			local button = vgui.Create('DButton', panel)
			button.Paint = function() end
			button:SetText('')
			button:Dock(FILL)

			-- re-colour when the mouse enters
			button.OnCursorEntered = function()
				panel:SetBackgroundColor(MENU_SELECTED)
				name:SetTextColor(MENU_BACKGROUND)
			end

			-- return colour to normal when mouse exits
			button.OnCursorExited = function()
				panel:SetBackgroundColor(MENU_BACKGROUND)
				name:SetTextColor(MENU_IDLE)
			end

			-- ask for the reason after clicking
			button.DoClick = function()
				-- do not send vote attempt if the player disconnected
				if IsValid(_player) then
					Derma_StringRequest(MENU_REASON_TITLE, string.format(MENU_REASON, _player:Name()), '', function(reason)
						-- send vote request
						net.Start(NET)
						net.WriteEntity(_player)
						net.WriteString(reason)
						net.SendToServer()

						-- close menu
						frame:Close()
					end)
				else
					Derma_Message(MENU_DISCONNECTED, MENU_DISCONNECTED_TITLE)
				end
			end

			-- add panel to list
			list:Add(panel)
		end
	end

	--[[------------------------------------------------------------------
		Initialize before drawing.
	]]--------------------------------------------------------------------
	createFonts()
	addNumber(NUMBER_YES)
	addNumber(NUMBER_NO)

	--[[------------------------------------------------------------------
		Draw the UI.
	]]--------------------------------------------------------------------
	hook.Add('HUDPaint', NET, function()
		-- if a custom HUD is drawn, do not draw default
		if hook.Run(HOOK_DRAW, vote) then return end

		-- get scale
		local scale = getScale()

		-- draw voting UI
		if vote.active then
			-- update numbers to trigger animation
			setNumber(NUMBER_YES, vote.yes)
			setNumber(NUMBER_NO, vote.no)

			 -- draw voting status
			drawStatus(ScrW() - X * scale, Y * scale, W, 192, scale, blink, blinkColour, vote.kicker, vote.kicked, vote.reason, math.floor(vote.time - CurTime()), vote.yes, vote.no, numbers[NUMBER_YES].amount, numbers[NUMBER_NO].amount)
		else
			-- do not draw if the display time is over
			if vote.result.display < CurTime() then return end

			-- choose result to display
			local result, colour = HUD_INSUFFICIENT, COLOUR_NEGATIVE
			if vote.result.result == RESULT_FAILURE then
				result = HUD_FAILURE
			elseif vote.result.result == RESULT_SUCCESS then
				result = string.format(HUD_SUCCESS, vote.kicked)
				colour = COLOUR_POSITIVE
			end

			-- draw veredict
			drawVeredict(ScrW() - X * scale, Y * scale, W, H, scale, blink, blinkColour, vote.kicker, vote.kicked, vote.reason, result, colour)
		end

		-- animate panel blink
		blink = math.max(blink - FrameTime() * BLINK_SPEED, 0)

		-- animate number blinking
		for id, number in pairs(numbers) do
			if number.blinked then
				numbers[id].amount = math.max(number.amount - FrameTime() * SCANLINES_OUT_SPEED, 0)
			else
				local amount = math.min(number.amount + FrameTime() * SCANLINES_IN_SPEED, 1)
				numbers[id].amount = amount
				if amount >= 1 then numbers[id].blinked = true end
			end
		end
	end)

	--[[------------------------------------------------------------------
		Detect when the player attempts quick-voting with key binds.
	]]--------------------------------------------------------------------
	hook.Add('CreateMove', NET, function(_)
		if vote.active and KEYS:GetBool() then
			if input.WasKeyPressed(KEY_YES:GetInt()) then
				RunConsoleCommand(CHAT_CONCOMMAND, COMMAND_YES)
			elseif input.WasKeyPressed(KEY_NO:GetInt()) then
				RunConsoleCommand(CHAT_CONCOMMAND, COMMAND_NO)
			end
		end
	end)

	--[[------------------------------------------------------------------
		Resize fonts when screen size changes.
	]]--------------------------------------------------------------------
	hook.Add('OnScreenSizeChanged', NET, createFonts)

	--[[------------------------------------------------------------------
		Called when the client is initialized -- displays the welcome message.
	]]--------------------------------------------------------------------
	hook.Add('Initialize', NET, function()
		local message = string.Explode(PLACEHOLDER, MESSAGE_WELCOME)
		chat.AddText(COLOUR_BASE, message[1], COLOUR_HOSTNAME, GetHostName(), COLOUR_BASE, message[2], COLOUR_NAME, NAME, COLOUR_BASE, message[3], VERSION, message[4], COLOUR_COMMAND, COMMAND_MENU, COLOUR_BASE, message[5])
	end)

	--[[------------------------------------------------------------------
		Create Q menu
	]]--------------------------------------------------------------------
	hook.Add('PopulateToolMenu', NET, function()
		-- voting menu
		spawnmenu.AddToolMenuOption( 'Options', 'DyaMetR', NET .. '_client', NAME, nil, nil, function(panel)
			panel:ClearControls()

			-- open voting menu
			panel:AddControl( 'Button', {
				Label = 'Open voting menu',
				Command = 'votekick_menu',
			})

			-- settings
			panel:AddControl( 'CheckBox', {
				Label = 'Use key binds to vote',
				Command = 'cl_votekick_usebinds'
			})

			panel:AddControl( 'Numpad', {
				Label = 'Vote yes',
				Command = 'cl_votekick_bind_yes'
			})

			panel:AddControl( 'Numpad', {
				Label = 'Vote no',
				Command = 'cl_votekick_bind_no'
			})

			-- credits
			panel:AddControl( 'Label',  { Text = '\nVersion ' .. VERSION })
			panel:AddControl( 'Label',  { Text = 'Made by DyaMetR' })
		end)

		-- admin menu
		spawnmenu.AddToolMenuOption( 'Utilities', 'DyaMetR', NET .. '_admin', NAME, nil, nil, function(panel)
			panel:ClearControls()

			-- header
			panel:AddControl( 'Label',  { Text = 'Administrator actions' })

			-- allow admins to abort votes
			panel:AddControl( 'Button', {
				Label = 'Abort current vote',
				Command = 'votekick_abort',
			})

			-- header
			panel:AddControl( 'Label',  { Text = 'Server settings' })

			-- settings
			panel:AddControl( 'CheckBox', {
				Label = 'Enabled',
				Command = 'sv_votekick'
			})

			panel:AddControl( 'CheckBox', {
				Label = 'Admin immunity',
				Command = 'sv_votekick_immuneadmins'
			})

			panel:AddControl( 'Slider', {
				Label = 'Ban time (in minutes)',
				Type = 'Float',
				Min = '0',
				Max = '120',
				Command = 'sv_votekick_bantime'
			})

			panel:AddControl( 'Slider', {
				Label = 'Vote duration (in seconds)',
				Type = 'Float',
				Min = '0',
				Max = '90',
				Command = 'sv_votekick_votetime'
			})

			panel:AddControl( 'Slider', {
				Label = 'Vote cooldown (in minutes)',
				Type = 'Float',
				Min = '0',
				Max = '60',
				Command = 'sv_votekick_cooldown'
			})

			panel:AddControl( 'Slider', {
				Label = 'Participation percentage required',
				Type = 'Float',
				Min = '0',
				Max = '100',
				Command = 'sv_votekick_minvotes'
			})

			panel:AddControl( 'Slider', {
				Label = 'Minimum players',
				Type = 'Integer',
				Min = '0',
				Max = '32',
				Command = 'sv_votekick_minplayers'
			})
		end)
	end)

	--[[------------------------------------------------------------------
		Opens the voting menu.
	]]--------------------------------------------------------------------
	concommand.Add(CONCOMMAND_MENU, menu)

	--[[------------------------------------------------------------------
		Receive new vote.
	]]--------------------------------------------------------------------
	net.Receive(NET, function(len)
		-- store information
		vote.kicker = net.ReadString()
		vote.kicked = net.ReadString()
		vote.reason = net.ReadString()
		vote.time = net.ReadFloat()
		vote.voters = net.ReadInt(NUMBER_SIZE)
		vote.yes = net.ReadInt(NUMBER_SIZE)
		vote.no = net.ReadInt(NUMBER_SIZE)
		vote.active = true

		-- do panel blink animation
		blink = 1
		blinkColour = COLOUR_TINT

		-- play sound
		playSound(SOUND_START, HOOK_SOUND_START)
	end)

	--[[------------------------------------------------------------------
		Receive a vote result.
	]]--------------------------------------------------------------------
	net.Receive(NET_END, function(len)
		vote.result.result = net.ReadInt(NUMBER_SIZE)
		vote.active = false

		-- only display for longer if the vote wasn't aborted
		if vote.result.result ~= RESULT_ABORT then
			-- select panel blinking colour
			if vote.result.result == RESULT_SUCCESS then
				blinkColour = COLOUR_POSITIVE
				playSound(SOUND_SUCCESS, HOOK_SOUND_SUCCESS)
			else
				blinkColour = COLOUR_NEGATIVE
				playSound(SOUND_FAILURE, HOOK_SOUND_FAILURE)
			end

			-- make panel blink
			blink = 1

			-- display veredict for some time
			vote.result.display = CurTime() + POST_VOTE_DISPLAY_TIME
		else
			playSound(SOUND_ABORT, HOOK_SOUND_ABORT)
		end
	end)

	--[[------------------------------------------------------------------
		Receive vote change.
	]]--------------------------------------------------------------------
	net.Receive(NET_VOTE, function(len)
		local yes = net.ReadBool()
		local add = net.ReadBool()

		-- check whether we should add or subtract
		local amount = 1
		if not add then amount = -1 end

		-- apply specific vote
		if yes then
			vote.yes = vote.yes + amount
		else
			vote.no = vote.no + amount
		end

		-- run hook
		hook.Run(HOOK_SOUND_VOTE, yes, add)
	end)

	--[[------------------------------------------------------------------
		Receive notification.
	]]--------------------------------------------------------------------
	net.Receive(NET_NOTIFY, function(len)
		local message = net.ReadString()
		local _type = net.ReadInt(TYPE_SIZE)
		local length = net.ReadFloat()
		notification.AddLegacy(message, _type, length)
		surface.PlaySound(NOTIFY_SOUNDS[math.Clamp(_type, NOTIFY_GENERIC, NOTIFY_CLEANUP) + 1])
	end)

end
