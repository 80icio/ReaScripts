-- @description amagalma_Toggle enclose selected or focused FX in vsible chain with AB_LM Level Matching VST/JSFX
-- @author amagalma
-- @version 1.0
-- @about
--   # Inserts or Removes TBProAudio's AB_LM Level Matching VST/JSFX enclosing the selected FXs or the focused FX (if not any selected)
--   - Automatically checks if AB_LM VST2, VST3 or JSFX are present in your system
--   - Ability to set in the script the prefered format of AB_LM (VST2, VST3 or JSFX)
--   - Smart undo point creation
-- @link http://www.tb-software.com/TBProAudio/ab_lm.html

------------------------------------------------------------------------------------------------
local reaper = reaper

--==========================================================================
local pref = 1 -- SET HERE YOUR PREFERENCE (1 = JSFX, 2 = VST2, 3 = VST3  ==
--==========================================================================

------------------------------------------------------------------------------------------------

-- INITIAL CHECKS
-- Check if js_ReaScriptAPI extension is installed
local js_vers = reaper.JS_ReaScriptAPI_Version()
if js_vers < 0.962 then
  reaper.MB( "You need js_ReaScriptAPI extension (v0.962 and newer) to run this script.", "Cannot run script!", 0 )
  reaper.defer(function() end)
  return
end

-- Check if AB_LM .dll or .vst3 or jsfx exist in your system
local jsfx, vst2, vst3 = false, false, false
local vst_ini= reaper.GetResourcePath() .. "\\reaper-vstplugins.ini"
local jsfx_ini = reaper.GetResourcePath() .. "\\reaper-jsfx.ini"
-- check for VST2/3 presence
local file = io.open (vst_ini)
for line in file:lines() do
  if line:match("AB_LM.dll") then
    vst2 = 2
  elseif line:match("AB_LM.vst3") then
    vst3 = 3
  end
  if vst2 and vst3 then break end
end
io.close(file)
-- check for JSFX presence
local file = io.open (jsfx_ini)
local cntrl, src = false, false
for line in file:lines() do
  if line:match("AB_LM_cntrl") then
    cntrl = true
  elseif line:match("AB_LM_src") then
    src = true
  end
  if cntrl and src then 
    jsfx = 1
    break 
  end
end
io.close(file)

if not vst2 and not vst3 and not jsfx then
  reaper.MB( "No AB_LM VST2/VST3/JSFX has been found on your system.", "Can't run the action!", 0 )
  reaper.defer(function() end)
  return
end

-- what to do if preference does not exist
if pref == 1 and not jsfx then
  pref = vst2 and vst2 or vst3
elseif pref == 2 and not vst2 then
  pref = vst3 and vst3 or jsfx
elseif pref == 3 and not vst3 then
  pref = vst2 and vst2 or jsfx
end

------------------------------------------------------------------------------------------------
local function GetInfo()
  local FX_win = reaper.JS_Window_Find("FX: ", false )
  local sel_FX, firstselFX, lastselFX = {}
  if FX_win then
    local title = reaper.JS_Window_GetTitle( FX_win, "" )
    if title:match("FX: Track ") or title:match("FX: Master Track") or title:match("FX: Item ") then
      local list = reaper.JS_Window_FindChildByID(FX_win, 1076)
      local _, sel_fx = reaper.JS_ListView_ListAllSelItems(list)
      local a = 0
      local sel_FX = {}
      for i in sel_fx:gmatch("%d+") do
        sel_FX[a+1] = tonumber(i)
        a = a + 1
      end
      local what, trackGUID, take
      reaper.JS_Window_SetForeground( FX_win ) -- GetFocusedFX works better
      local focus, track, item, fxid = reaper.GetFocusedFX()
      if focus == 1 then
        what = "track"
        if track == 0 then
          track = reaper.GetMasterTrack(0)
        else
          track = reaper.GetTrack(0, track-1)
        end
        trackGUID = reaper.guidToString(reaper.GetTrackGUID(track), "")
      elseif focus == 2 then
        what = "item"
        item = reaper.GetMediaItem(0, item)
        track = reaper.GetMediaItemTrack(item)
        trackGUID = reaper.guidToString(reaper.GetTrackGUID(track), "")
        take = reaper.GetMediaItemTake(item, fxid >> 16)
      end
      if #sel_FX > 1 then
        firstselFX = sel_FX[1]
        lastselFX = sel_FX[#sel_FX]
      end
      return fxid, track, what, trackGUID, take, firstselFX, lastselFX
    else
      return nil
    end
  end
end

------------------------------------------------------------------------------------------------
local function AddTrackAB(track, pos, x)
  if pref == 1 then
    if x == 1 then
      reaper.TrackFX_AddByName(track, "JS:AB_LM_src", false, -1)
    else
      reaper.TrackFX_AddByName(track, "JS:AB_LM_cntrl", false, -1)
    end
  elseif pref == 2 then
    reaper.TrackFX_AddByName(track, "VST2:AB_LM", false, -1)
  elseif pref == 3 then
    reaper.TrackFX_AddByName(track, "VST3:AB_LM", false, -1)
  end
  reaper.TrackFX_CopyToTrack(track, reaper.TrackFX_GetCount( track )-1, track, pos, true )
end

local function AddTakeAB(take, pos, x)
 if pref == 1 then
   if x == 1 then
     reaper.TakeFX_AddByName(take, "JS:AB_LM_src", -1)
   else
     reaper.TakeFX_AddByName(take, "JS:AB_LM_cntrl", -1)
   end 
  elseif pref == 2 then
    reaper.TakeFX_AddByName( take, "VST2:AB_LM", -1 )
  elseif pref == 3 then
    reaper.TakeFX_AddByName( take, "VST3:AB_LM", -1 )
  end
  reaper.TakeFX_CopyToTake( take, reaper.TakeFX_GetCount( take )-1, take, pos, true )
end

------------------------------------------------------------------------------------------------
local function AlterChunk(chunk, lastselFX, focusedFX, fxid, t)
  local cnt = -1
  local float = false
  for line in chunk:gmatch('[^\n]+') do
    if cnt == -1 and line:match("^SHOW %d+$") then -- keep previously focused FX focused
      line = "SHOW " .. tostring(lastselFX ~= nil and focusedFX+1 or fxid+2)
      cnt = 0
    end
    if pref ~= 1 then -- VST
      if line:match("<VST.-AB_LM") and cnt < 2 then
        if cnt == 0 then
          line = line:gsub('(.-)""(.+)', '%1"-- AB_LM Send --"%2')
          cnt = cnt + 1
        else
          line = line:gsub('(.-)""(.+)', '%1"-- AB_LM Receive --"%2')
          cnt = cnt + 1
        end
      elseif not float and cnt == 2 and line:match("FLOATPOS") then -- float AB_LM Receive
        line = "FLOAT 1230 180 440 671"
        float = true
      end
    else -- JSFX
      if line:match("<JS.-AB_LM_src") and cnt < 1 then
        line = line:gsub('(.-)""', '%1"-- AB_LM Send --"')
        cnt = cnt + 1
      elseif (line:match("<JS.-AB_LM_cntrl") and cnt < 2) then  
        line = line:gsub('(.-)""', '%1"-- AB_LM Receive --"')
        cnt = cnt + 1
      elseif not float and cnt == 2 and line:match("FLOATPOS") then -- float AB_LM Receive
        line = "FLOAT 1052 56 573 956"
        float = true
      end
    end
    t[#t+1] = line
  end
end

------------------------------------------------------------------------------------------------
local function InsertAB(fxid, track, what, trackGUID, take, firstselFX, lastselFX)
  local focusedFX = fxid
  if lastselFX and focusedFX >= firstselFX and focusedFX <= lastselFX then
    focusedFX = fxid + 1
  elseif lastselFX and focusedFX > lastselFX then
    focusedFX = fxid + 2
  end
  if what == "track" then
    if lastselFX then -- enclose selected FXs
      AddTrackAB(track, firstselFX, 1)
      AddTrackAB(track, lastselFX+2, 2)
    else -- enclose focused FX
      AddTrackAB(track, fxid, 1)
      AddTrackAB(track, fxid+2, 2)
    end
    local _, chunk = reaper.GetTrackStateChunk( track, "", false )
    local t = {}
    AlterChunk(chunk, lastselFX, focusedFX, fxid, t)
    chunk = table.concat(t, "\n")
    reaper.SetTrackStateChunk( track, chunk, false )
  elseif what == "item" then
    if lastselFX then -- enclose selected FXs
      AddTakeAB(take, firstselFX, 1)
      AddTakeAB(take, lastselFX+2, 2)
    else -- enclose focused FX
      AddTakeAB(take, fxid, 1)
      AddTakeAB(take, fxid+2, 2)
    end
    local item = reaper.GetMediaItemTake_Item( take )
    local _, chunk = reaper.GetItemStateChunk( item, "", false )
    local t = {}
    AlterChunk(chunk, lastselFX, focusedFX, fxid, t)
    chunk = table.concat(t, "\n")
    reaper.SetItemStateChunk( item, chunk, false )
  end
end

------------------------------------------------------------------------------------------------
local function RemoveAB(track, what, take)
  if what == "track" then
    local id = reaper.TrackFX_GetByName( track, "-- AB_LM Receive --", false )
    reaper.TrackFX_Delete( track, id)
    id = reaper.TrackFX_GetByName( track, "-- AB_LM Send --", false )
    reaper.TrackFX_Delete( track, id)
  elseif what == "item" then
    local id = reaper.TakeFX_AddByName( take, "-- AB_LM Receive --", 0 )
    reaper.TakeFX_Delete( take, id )
    id = reaper.TakeFX_AddByName( take, "-- AB_LM Send --", 0 )
    reaper.TakeFX_Delete( take, id )
  end
end

-- Main function -------------------------------------------------------------------------------
local fxid, track, what, trackGUID, take, firstselFX, lastselFX = GetInfo()
if track and trackGUID then
  local ok, value = reaper.GetProjExtState(0, "AB_LM VST Toggle", trackGUID)
  if ok and value == "1" then
    reaper.Undo_BeginBlock()
    RemoveAB(track, what, take)
    reaper.SetProjExtState(0, "AB_LM VST Toggle", trackGUID, "0")
    reaper.Undo_EndBlock("Remove AB_LM VST from focused FX Chain", -1)
  else
    reaper.Undo_BeginBlock()
    InsertAB(fxid, track, what, trackGUID, take, firstselFX, lastselFX)
    reaper.SetProjExtState(0, "AB_LM VST Toggle", trackGUID, "1")
    reaper.Undo_EndBlock("Enclose selected/focused FX in Chain with AB_LM VST", -1)
  end
else
  reaper.defer(function() end)
end