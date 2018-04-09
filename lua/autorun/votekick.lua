--[[-----------------

	SIMPLE VOTEKICK SYSTEM
	by DyaMetR

	Version 1.0.1
	17/04/17

]]-------------------


local VERSION = "1.0.1"
if SERVER then
	util.AddNetworkString("votekick")
	util.AddNetworkString("votekickMenu")

	CreateConVar("votekick_ban",5,FCVAR_ARCHIVE)
	CreateConVar("votekick_cooldown",30,FCVAR_ARCHIVE)

	local VOTEKICK = {
		yes = {},
		no = {},
		reason = "",
		kicker = nil,
		kicked = nil,
		time = 0
	}

	local function SendData(endVote, forceEnd)
		net.Start("votekick")
			net.WriteFloat(table.Count(VOTEKICK.yes))
			net.WriteFloat(table.Count(VOTEKICK.no))
			net.WriteString(VOTEKICK.reason)
			if IsValid(VOTEKICK.kicker) then
				net.WriteString(VOTEKICK.kicker:Nick())
			else
				net.WriteString("Disconnected")
			end
			if IsValid(VOTEKICK.kicked) then
				net.WriteString(VOTEKICK.kicked:Nick())
			else
				net.WriteString("Disconnected")
			end
			net.WriteFloat(VOTEKICK.time)
			net.WriteBool(endVote)
			net.WriteBool(forceEnd or false)
		net.Broadcast()
	end

	local function Reset()
		VOTEKICK.yes = {}
		VOTEKICK.no = {}
		VOTEKICK.reason = ""
		VOTEKICK.kicker = nil
		VOTEKICK.kicked = nil
		VOTEKICK.time = 0
		timer.Remove("votekick")
	end

	local function Veredict()
		if IsValid(VOTEKICK.kicker) and IsValid(VOTEKICK.kicked) then
			if table.Count(VOTEKICK.yes) > table.Count(VOTEKICK.no) and (table.Count(VOTEKICK.yes)+table.Count(VOTEKICK.no)) > table.Count(player.GetAll())/2 then
				VOTEKICK.kicked:Kick("You've been voted off. Come back in "..GetConVar("votekick_ban"):GetInt().." minutes.")
				VOTEKICK.kicked:Ban(GetConVar("votekick_ban"):GetInt())
			end
			SendData(true)
			Reset()
		else
			Reset()
		end
	end

	local function Start(ply, kicked, reason)
		if ply.votekickCooldown == nil or ply.votekickCooldown < CurTime() then
			if !timer.Exists("votekick") then
				VOTEKICK.kicked = kicked
				VOTEKICK.kicker = ply
				VOTEKICK.reason = reason
				table.insert(VOTEKICK.yes, VOTEKICK.kicker)
				table.insert(VOTEKICK.no, VOTEKICK.kicked)
				if table.Count(player.GetAll()) > 2 then
					VOTEKICK.time = CurTime() + 30
					timer.Create("votekick",30,1,function()
						Veredict()
					end)
					SendData()
				else
					VOTEKICK.time = CurTime()
					SendData()
					Veredict()
				end
				ply.votekickCooldown = CurTime() + GetConVar("votekick_cooldown"):GetInt()
			else
				ply:ChatPrint("There's already a vote in progress!")
			end
		else
			ply:ChatPrint("You need to wait "..math.ceil(ply.votekickCooldown - CurTime()).." seconds before making another vote!")
		end
	end

	local function EveryoneVoted()
		if (table.Count(VOTEKICK.yes)+table.Count(VOTEKICK.no)) >= table.Count(player.GetAll()) then
			SendData(true)
			Veredict()
		else
			SendData(false)
		end
	end

	local function Chat(ply,msg,team)
		if table.HasValue({"!yes","!no"}, msg) and timer.Exists("votekick") then
			if !table.HasValue(VOTEKICK.yes, ply) and !table.HasValue(VOTEKICK.no, ply) then
				if msg == "!yes" then
					table.insert(VOTEKICK.yes, ply)
					EveryoneVoted()
				elseif msg == "!no" then
					table.insert(VOTEKICK.no, ply)
					EveryoneVoted()
				end
				return ""
			end
		end
		if msg == "!votekick" then
			net.Start("votekickMenu")
			net.Send(ply)
			return ""
		end
	end
	hook.Add("PlayerSay", "votekick_chat", Chat)

	local function Disconnect(ply)
		if VOTEKICK.kicked == ply then
			VOTEKICK.kicked:Kick("You've left while being voted off. Come back in "..GetConVar("votekick_ban"):GetInt().." minutes.")
			VOTEKICK.kicked:Ban(GetConVar("votekick_ban"):GetInt())
			SendData(true,true)
			Reset()
		end
		if VOTEKICK.kicker == ply then
			SendData(true,true)
			Reset()
		end
		if table.HasValue(VOTEKICK.yes, ply) then
			table.remove(VOTEKICK.yes, table.KeyFromValue(VOTEKICK.yes, ply))
		end
		if table.HasValue(VOTEKICK.no, ply) then
			table.remove(VOTEKICK.no, table.KeyFromValue(VOTEKICK.no, ply))
		end
	end
	hook.Add("PlayerDisconnected","votekick_disconnect", Disconnect)

	local function Spawn(ply)
		ply:ChatPrint("This server is running Simple Votekick System version "..VERSION..". Say !votekick to open the menu.")
	end
	hook.Add("PlayerInitialSpawn","votekick_spawn",Spawn)

	net.Receive("votekick", function(len,ply)
		local data1 = net.ReadEntity()
		local data2 = net.ReadString()
		if data2 == "" then
			ply:ChatPrint("You need to specify a reason!")
		else
			Start(ply, data1, data2)
		end
	end)
end

if CLIENT then
	surface.CreateFont( "votekick1", {
	    font = "Tahoma",
	    extended = false,
	    size = 18,
	    weight = 1000,
	    blursize = 0,
	    scanlines = 0,
	    antialias = true
	} )

	surface.CreateFont( "votekick2", {
	    font = "Tahoma",
	    extended = false,
	    size = 24,
	    weight = 600,
	    blursize = 0,
	    scanlines = 0,
	    antialias = true
	} )
	surface.CreateFont( "votekick2b", {
	    font = "Tahoma",
	    extended = false,
	    size = 24,
	    weight = 600,
	    blursize = 4,
	    scanlines = 2,
	    antialias = true,
	    additive = true
	} )

	surface.CreateFont( "votekick3a", {
	    font = "HalfLife2",
	    extended = false,
	    size = 34,
	    weight = 500,
	    blursize = 0,
	    scanlines = 0,
	    antialias = true,
	    additive = true
	} )
	surface.CreateFont( "votekick3b", {
	    font = "HalfLife2",
	    extended = false,
	    size = 34,
	    weight = 500,
	    blursize = 4,
	    scanlines = 2,
	    antialias = true,
	    additive = true
	} )

	surface.CreateFont( "votekick4", {
	    font = "Tahoma",
	    extended = false,
	    size = 21,
	    weight = 600,
	    blursize = 0,
	    scanlines = 0,
	    antialias = true
	} )

	local w,h = 300,145
	local fade1 = 0
	local fade2 = 0
	local fadet = 0
	local votekick = {fade = 0, time = 0, yes = 0, no = 0, reason = "", kicker = "", kicked = "", endVote = true}
	local function DrawPanel(x,y)
			if fadet < CurTime() then
				if fade1 > 0 then
					fade1 = fade1 - 0.01
				end
				if fade2 > 0 then
					fade2 = fade2 - 0.01
				end
				fadet = CurTime() + 0.02
			end
	    draw.RoundedBox(6,x,y,w,h,Color(0,0,0,50))
	    draw.SimpleText("VOTEKICK", "HudSelectionText", x + 8,y + 8,Color(255,245,50,255))
			local t = math.floor(votekick.time - CurTime())
	    draw.SimpleText(math.Clamp(t,0,t), "HudSelectionText", x + (w-10),y + 8,Color(255,245,50,255), 2)
	    draw.SimpleText(votekick.kicker, "votekick1", x + 10,y + 24,Color(255,245,50,255))
	    draw.SimpleText("Kick "..votekick.kicked.."?", "votekick2", x + 8,y + 41,Color(255,245,50,255))
	    draw.SimpleText("'"..votekick.reason.."'", "votekick4", x + 8,y + 64,Color(255,245,50,255))
	    draw.SimpleText("!yes", "votekick1", x + 139,y + 93,Color(255,245,50,255),2)
	    draw.SimpleText("!no", "votekick1", x + 158,y + 93,Color(255,245,50,255))
	    draw.SimpleText(votekick.yes, "votekick3a", x + 8,y + 83,Color(100,255,0,255))
	    draw.SimpleText(votekick.yes, "votekick3b", x + 8,y + 83,Color(100,255,0,255*fade1))
	    draw.SimpleText(votekick.no, "votekick3a", x + (w-10),y + 83,Color(255,50,0,255),2)
	    draw.SimpleText(votekick.no, "votekick3b", x + (w-10),y + 83,Color(255,50,0,255*fade2),2)
	    for i=0,10 do
	        draw.RoundedBox(0,x+11 + i*12,y+119,9,15,Color(0,0,0,75))
	        draw.RoundedBox(0,x+(w-21) - i*12,y+119,9,15,Color(0,0,0,75))
	    end
	    for i=0,math.floor((votekick.yes/(table.Count(player.GetAll())-1))*10) do
	        draw.RoundedBox(0,x+11 + i*12,y+119,9,15,Color(100,255,0,255))
	    end
	    for i=0,math.floor((votekick.no/(table.Count(player.GetAll())-1))*10) do
	        draw.RoundedBox(0,x+(w-21) - i*12,y+119,9,15,Color(255,75,0,255))
	    end
	end
	local function Veredict(x,y)
			if fadet < CurTime() then
				if fade1 > 0 then
					fade1 = fade1 - 0.01
				end
				fadet = CurTime() + 0.02
			end
	    draw.RoundedBox(6,x,y,w,h-30,Color(0,0,0,50))
	    draw.SimpleText("VOTEKICK", "HudSelectionText", x + 8,y + 8,Color(255,245,50,255))
	    draw.SimpleText(votekick.kicker, "votekick1", x + 10,y + 24,Color(255,245,50,255))
	    draw.SimpleText("Kick "..votekick.kicked.."?", "votekick2", x + 8,y + 41,Color(255,245,50,255))
	    draw.SimpleText("'"..votekick.reason.."'", "votekick4", x + 8,y + 64,Color(255,245,50,255))
	    if ((votekick.yes > votekick.no) && (votekick.yes+votekick.no > math.ceil(table.Count(player.GetAll())/2))) && (votekick.yes+votekick.no >= table.Count(player.GetAll()) || votekick.time < CurTime()) then
	        draw.SimpleText("Vote passed!", "votekick2", x + 10,y + 85,Color(100,255,0,255))
	        draw.SimpleText("Vote passed!", "votekick2b", x + 10,y + 85,Color(100,255,0,255*fade1))
	    else
	        draw.SimpleText("Vote denied", "votekick2", x + 10,y + 85,Color(255,30,20,255))
	        draw.SimpleText("Vote denied", "votekick2b", x + 10,y + 85,Color(255,30,20,255*fade1))
	    end
	end

	local function HUD()
			if votekick.endVote then
				if votekick.fade > CurTime() then
	    		Veredict(ScrW() - (w+20), 20)
				end
			else
				if votekick.time >= CurTime() then
					DrawPanel(ScrW() - (w+20), 20)
				end
			end
	end
	hook.Add("HUDPaint", "hud", HUD)

	net.Receive("votekick",function(len)
		local data1 = net.ReadFloat()
		local data2 = net.ReadFloat()
		local data3 = net.ReadString()
		local data4 = net.ReadString()
		local data5 = net.ReadString()
		local data6 = net.ReadFloat()
		local data7 = net.ReadBool()
		local data8 = net.ReadBool()
		if data1 != votekick.yes then
			fade1 = 1
			if data1 > 1 then
				surface.PlaySound("buttons/blip1.wav")
			end
		end
		if data2 != votekick.no then
			fade2 = 1
			if data2 > 1 then
				surface.PlaySound("buttons/button10.wav")
			end
		end
		if data4 != votekick.kicker or data5 != votekick.kicked then
			surface.PlaySound("common/warning.wav")
		end
		votekick.yes = data1
		votekick.no = data2
		votekick.reason = data3
		votekick.kicker = data4
		votekick.kicked = data5
		votekick.time = data6
		votekick.endVote = data7
		if data7 then
			fade1 = 1
			votekick.fade = CurTime() + 4
		end
		if data8 then
			votekick.yes = 0
		end
	end)

	local function Menu()
		local frame = vgui.Create("DFrame")
		frame:SetSize(500,500)
		frame:SetPos((ScrW()/2) - (frame:GetWide()/2), (ScrH()/2) - (frame:GetTall()/2))
		frame:SetTitle("Votekick")
		frame:MakePopup()
			local sc = vgui.Create("DScrollPanel", frame)
			sc:SetPos(5,30)
			sc:SetSize(frame:GetWide()-10,frame:GetTall()-57)
				local pl = vgui.Create("DIconLayout", sc)
				pl:SetPos(0,0)
				pl:SetSize(sc:GetWide(), sc:GetTall())
				pl:SetSpaceY(5)
					for k,v in pairs(player.GetAll()) do
						if v != LocalPlayer() then
							local panel = vgui.Create("DPanel")
							panel:SetSize(pl:GetWide(),32)
								local avatar = vgui.Create("AvatarImage", panel)
								avatar:SetPos(0,0)
								avatar:SetSize(32,32)
								avatar:SetPlayer(v, 32)
								local name = vgui.Create("DLabel", panel)
								name:SetPos(42,10)
								name:SetText(v:Nick())
								name:SetFont("DermaDefaultBold")
								name:SetTextColor(Color(40,40,40))
								name:SizeToContents()
								local but = vgui.Create("DButton", panel)
								but:SetPos(0,0)
								but:SetSize(panel:GetWide(), panel:GetTall())
								but:SetText("")
								but.Paint = function() end
								but.DoClick = function()
									Derma_StringRequest("Kick player","Why would you like to kick "..v:Nick().."?","",function(text) net.Start("votekick") net.WriteEntity(v) net.WriteString(text) net.SendToServer() frame:Close() end,nil,"Accept","Cancel")
								end
							pl:Add(panel)
						end
					end
		local label = vgui.Create("DLabel", frame)
		label:SetText("Version "..VERSION)
		label:SetPos(8,frame:GetTall() - 22)
		label:SetTextColor(Color(80,80,80))
		label:SetFont("DermaDefaultBold")
		label:SizeToContents()
		local owner = vgui.Create("DLabel", frame)
		owner:SetText("DyaMetR")
		owner:SetPos(frame:GetWide() - 60,frame:GetTall() - 22)
		owner:SetTextColor(Color(80,80,80))
		owner:SetFont("DermaDefaultBold")
		owner:SizeToContents()
	end

	net.Receive("votekickMenu", function(len)
		Menu()
	end)

	local function menu( Panel )
		Panel:ClearControls()
		Panel:AddControl( "Label" , { Text = "Simple Votekick System Settings", Description = ""} )
		Panel:AddControl( "Slider", {
			Label = "Kick duration",
			Type = "Short",
			Min = "1",
			Max = "60",
			Command = "votekick_ban",
			}
		)
		Panel:AddControl( "Slider", {
			Label = "Vote cooldown",
			Type = "Short",
			Min = "0",
			Max = "600",
			Command = "votekick_cooldown",
			}
		)
		Panel:AddControl( "Button", {
			Label = "Open menu",
			Command = "say !votekick",
			}
		)
		Panel:AddControl( "Label",  { Text = "Version "..VERSION, Description = ""})
	end

	local function createMenu()
		spawnmenu.AddToolMenuOption( "Options", "DyaMetR", "VOTEKICK", "Simple Votekick System", "", "", menu )
	end
	hook.Add( "PopulateToolMenu", "votekickOptions", createMenu )
end
