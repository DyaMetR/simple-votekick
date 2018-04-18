-----------------------------
-- SIMPLE VOTEKICK SYSTEM
-- by DyaMetR
--
-- Version 1.0.1
-- 17/04/17
-----------------------------
if not SERVER then
  return false

VERSION = '1.0.1'

class Vote
  new: =>
    @yes = {}
    @no = {}
    @reason = ""
    @kicker = nil
    @kicked = nil
    @time = 0

VOTEKICK = Vote!

class VoteKick
  SendData: (endVote, forceEnd) ->
    net.Start("votekick")
      net.WriteFloat(table.Count(VOTEKICK.yes))
      net.WriteFloat(table.Count(VOTEKICK.no))
      net.WriteString(VOTEKICK.reason)
      if IsValid(VOTEKICK.kicker) then
        net.WriteString(VOTEKICK.kicker\Nick())
      else
        net.WriteString("Disconnected")
      if IsValid(VOTEKICK.kicked) then
        net.WriteString(VOTEKICK.kicked\Nick())
      else
        net.WriteString("Disconnected")
      net.WriteFloat(VOTEKICK.time)
      net.WriteBool(endVote)
      net.WriteBool(forceEnd or false)
    net.Broadcast()

  Reset: () ->
    VOTEKICK = Vote!
    timer.Remove("votekick")

  Veredict: () ->
    if IsValid(VOTEKICK.kicker) and IsValid(VOTEKICK.kicked) then
      if table.Count(VOTEKICK.yes) > table.Count(VOTEKICK.no) and (table.Count(VOTEKICK.yes)+table.Count(VOTEKICK.no)) > table.Count(player.GetAll())/2 then
        VOTEKICK.kicked\Kick("You've been voted off. Come back in #{GetConVar("votekick_ban")\GetInt()} minutes.")
        VOTEKICK.kicked\Ban(GetConVar("votekick_ban")\GetInt())
      VoteKick.SendData(true)
      VoteKick.Reset()
    else
      VoteKick.Reset()

  Start: (ply, kicked, reason) ->
    if ply.votekickCooldown == nil or ply.votekickCooldown < CurTime() then
      if !timer.Exists("votekick") then
        VOTEKICK.kicked = kicked
        VOTEKICK.kicker = ply
        VOTEKICK.reason = reason
        table.insert(VOTEKICK.yes, VOTEKICK.kicker)
        table.insert(VOTEKICK.no, VOTEKICK.kicked)
        if table.Count(player.GetAll()) > 2 then
          VOTEKICK.time = CurTime() + 30
          timer.Create "votekick", 30, 1, ->
            VoteKick.Veredict()
          SendData()
        else
          VOTEKICK.time = CurTime()
          VoteKick.SendData()
          VoteKick.Veredict()
        ply.votekickCooldown = CurTime() + GetConVar("votekick_cooldown")\GetInt()
      else
        ply\ChatPrint("There's already a vote in progress!")
    else
      ply\ChatPrint("You need to wait #{math.ceil(ply.votekickCooldown - CurTime())} seconds before making another vote!")

  EveryoneVoted: () ->
    if (table.Count(VOTEKICK.yes)+table.Count(VOTEKICK.no)) >= table.Count(player.GetAll()) then
      VoteKick.SendData(true)
      VoteKick.Veredict()
    else
      VoteKick.SendData(false)

  Chat: (ply,msg,team) ->
    if table.HasValue({"!yes","!no"}, msg) and timer.Exists("votekick") then
      if !table.HasValue(VOTEKICK.yes, ply) and !table.HasValue(VOTEKICK.no, ply) then
        if msg == "!yes" then
          table.insert(VOTEKICK.yes, ply)
          VoteKick.EveryoneVoted()
        elseif msg == "!no" then
          table.insert(VOTEKICK.no, ply)
          VoteKick.EveryoneVoted()
        return ""
    if msg == "!votekick" then
      net.Start("votekickMenu")
      net.Send(ply)
      return ""

  Disconnect: (ply) ->
    if VOTEKICK.kicked == ply then
      VOTEKICK.kicked\Kick("You've left while being voted off. Come back in #{GetConVar("votekick_ban")\GetInt()} minutes.")
      VOTEKICK.kicked\Ban(GetConVar("votekick_ban")\GetInt())
      SendData(true,true)
      VoteKick.Reset()
    if VOTEKICK.kicker == ply then
      VoteKick.SendData(true,true)
      VoteKick.Reset()
    if table.HasValue(VOTEKICK.yes, ply) then
      table.remove(VOTEKICK.yes, table.KeyFromValue(VOTEKICK.yes, ply))
    if table.HasValue(VOTEKICK.no, ply) then
      table.remove(VOTEKICK.no, table.KeyFromValue(VOTEKICK.no, ply))

  Spawn: (ply) ->
    ply\ChatPrint("This server is running Simple Votekick System version #{VERSION}. Say !votekick to open the menu.")

hook.Add("PlayerSay", "votekick_chat", Votekick.Chat)
hook.Add("PlayerDisconnected","votekick_disconnect", Votekick.Disconnect)
hook.Add("PlayerInitialSpawn","votekick_spawn", Votekick.Spawn)

net.Receive "votekick", (len,ply) ->
  data1 = net.ReadEntity()
  data2 = net.ReadString()
  if data2 == "" then
    ply\ChatPrint("You need to specify a reason!")
  else
    Start(ply, data1, data2)
