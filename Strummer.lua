-- ============================================================
-- Strummer.lua  v0.2
-- Guitar Strum Simulator for Reaper
-- Requires: ReaImGui + js_ReaScriptAPI (install via ReaPack)
-- ============================================================

if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox(
    "Please install ReaImGui via ReaPack first!\n(Extensions > ReaPack > Browse packages > search ReaImGui)",
    "Strummer: Missing dependency", 0)
  return
end

-- ============================================================
-- §1  Constants
-- ============================================================
local SCRIPT_NAME = "Strummer"
local VERSION     = "0.3"

-- Guitar standard tuning E2 A2 D3 G3 B3 E4
local GUITAR_STRINGS = {40, 45, 50, 55, 59, 64}

local CHORD_TYPES = {
  {name="Major",    intervals={0,4,7}       },
  {name="Minor",    intervals={0,3,7}       },
  {name="Dom7",     intervals={0,4,7,10}    },
  {name="Maj7",     intervals={0,4,7,11}    },
  {name="Min7",     intervals={0,3,7,10}    },
  {name="Sus2",     intervals={0,2,7}       },
  {name="Sus4",     intervals={0,5,7}       },
  {name="Power5",   intervals={0,7}         },
  {name="Dim",      intervals={0,3,6}       },
  {name="Aug",      intervals={0,4,8}       },
  {name="Add9",     intervals={0,4,7,14}    },
  {name="Min9",     intervals={0,3,7,10,14} },
}

-- Technique keys: all ASCII to avoid ImGui font CJK rendering issues
local TECHNIQUES  = {"Nrm","Mut","Hrm","Slp"}
local TECH_FULL   = {Nrm="Normal", Mut="Mute", Hrm="Harmonic", Slp="Slap"}
local TECH_COLORS = {
  Nrm=0x4FC3F7FF, Mut=0x90A4AEFF, Hrm=0xA5D6A7FF, Slp=0xFFB74DFF,
}

-- MIDI note name helpers
local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local function midi_to_name(n)
  local oct = math.floor(n / 12) - 1
  return NOTE_NAMES[(n % 12) + 1] .. oct
end
local function name_to_midi(s)
  local nm, oct = s:match("^([A-Ga-g]#?)(-?%d+)$")
  if not nm then return nil end
  local nm_map = {
    C=0,["C#"]=1,D=2,["D#"]=3,E=4,F=5,
    ["F#"]=6,G=7,["G#"]=8,A=9,["A#"]=10,B=11
  }
  local ni = nm_map[nm:upper()]
  if ni == nil then return nil end
  return (tonumber(oct)+1)*12 + ni
end

-- ============================================================
-- §2  Technique KeySwitch / CC Mapping table
-- ============================================================
-- type  = "none" | "ks_note" | "cc"
-- chan  = 0-15 (0-indexed MIDI channel)
-- note  = MIDI note number  (for ks_note)
-- cc_num= CC number 0-127   (for cc)
-- cc_val= CC value  0-127   (for cc)
-- pre_ticks = ticks before the strum to send the KS/CC
local TECH_MAP_DEFAULT = {
  Nrm = {type="none"},
  Mut = {type="none"},
  Hrm = {type="ks_note", chan=0, note=0,   pre_ticks=4},  -- C-1
  Slp = {type="ks_note", chan=0, note=2,   pre_ticks=4},  -- D-1
}

local function copy_tech_map(tm)
  local n = {}
  for k,v in pairs(tm) do
    n[k] = {type=v.type, chan=v.chan, note=v.note,
             cc_num=v.cc_num, cc_val=v.cc_val, pre_ticks=v.pre_ticks}
  end
  return n
end

-- ============================================================
-- §3  Pattern Library
-- ============================================================
local function S(on, dir, vel, off, tech, span)
  return {on=on, dir=dir, vel=vel, offset=off or 0, tech=tech or "Nrm", span=span or 1}
end
local D, U, X = true, true, false

local PATTERN_LIBRARY = {

  -- ── POP ──────────────────────────────────────────────────
  {name="Pop Basic 4/4",      genre="Pop",     bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00), S(X,"D",0), S(D,"D",0.80), S(D,"U",0.60),
    S(D,"D",0.90), S(X,"U",0), S(D,"D",0.80), S(D,"U",0.70),
  }},
  {name="Pop Lyric 4/4",      genre="Pop",     bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",0.90), S(D,"U",0.55), S(D,"D",0.75), S(D,"U",0.50),
    S(D,"D",0.85), S(D,"U",0.55), S(D,"D",0.75), S(D,"U",0.50),
  }},
  {name="Pop Ballad 4/4",     genre="Pop",     bars=1, timesig={4,4}, subdivisions=4, steps={
    S(D,"D",0.85), S(D,"D",0.75), S(D,"D",0.80), S(D,"U",0.65),
  }},
  {name="Pop 16th Drive",     genre="Pop",     bars=1, timesig={4,4}, subdivisions=16, steps={
    S(D,"D",1.00), S(D,"U",0.55), S(D,"D",0.65), S(D,"U",0.50),
    S(D,"D",0.90), S(D,"U",0.55), S(X,"D",0   ), S(D,"U",0.50),
    S(D,"D",0.95), S(D,"U",0.55), S(D,"D",0.65), S(D,"U",0.55),
    S(D,"D",0.85), S(D,"U",0.60), S(D,"D",0.70), S(D,"U",0.50),
  }},

  -- ── ROCK ─────────────────────────────────────────────────
  {name="Rock Power 4/4",     genre="Rock",    bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00), S(D,"D",0.90), S(X,"U",0   ), S(D,"D",0.95),
    S(D,"D",1.00), S(D,"U",0.70), S(X,"D",0   ), S(D,"D",0.90),
  }},
  {name="Rock 16th 4/4",      genre="Rock",    bars=1, timesig={4,4}, subdivisions=16, steps={
    S(D,"D",1.00), S(X,"U",0   ), S(D,"D",0.70), S(D,"U",0.60),
    S(D,"D",0.90), S(X,"U",0   ), S(D,"U",0.65), S(X,"D",0   ),
    S(D,"D",1.00), S(X,"U",0   ), S(D,"D",0.70), S(D,"U",0.60),
    S(D,"D",0.85), S(D,"U",0.70), S(X,"D",0   ), S(D,"U",0.60),
  }},
  {name="Metal Gallop 4/4",   genre="Rock",    bars=1, timesig={4,4}, subdivisions=12, steps={
    S(D,"D",1.00), S(D,"D",0.85), S(D,"D",0.80),
    S(D,"D",1.00), S(D,"D",0.85), S(D,"D",0.80),
    S(D,"D",1.00), S(D,"D",0.85), S(D,"D",0.80),
    S(D,"D",1.00), S(D,"D",0.85), S(D,"D",0.80),
  }},
  {name="Hard Rock Chug",     genre="Rock",    bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00,0,"Mut"), S(D,"D",0.90,0,"Mut"), S(D,"D",0.95,0,"Mut"), S(X,"U",0),
    S(D,"D",1.00,0,"Mut"), S(D,"D",0.85,0,"Mut"), S(D,"D",0.90,0,"Mut"), S(D,"U",0.70),
  }},

  -- ── JAZZ ─────────────────────────────────────────────────
  {name="Jazz Swing 4/4",     genre="Jazz",    bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",0.90,0), S(X,"U",0), S(D,"U",0.60,6), S(X,"D",0),
    S(D,"D",0.85,0), S(X,"U",0), S(D,"U",0.65,6), S(X,"D",0),
  }},
  {name="Jazz Bossa 2bar",    genre="Jazz",    bars=2, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",0.90), S(X,"U",0   ), S(X,"D",0   ), S(D,"U",0.65),
    S(D,"D",0.80), S(X,"U",0   ), S(X,"D",0   ), S(D,"U",0.60),
    S(D,"D",0.85), S(D,"U",0.55), S(X,"D",0   ), S(D,"U",0.60),
    S(D,"D",0.80), S(X,"U",0   ), S(X,"D",0   ), S(D,"U",0.55),
  }},
  {name="Jazz Comping 2bar",  genre="Jazz",    bars=2, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",0.85), S(X,"U",0   ), S(D,"U",0.55,5), S(X,"D",0),
    S(X,"D",0   ), S(D,"U",0.65,5), S(D,"D",0.80), S(X,"U",0),
    S(D,"D",0.80), S(X,"U",0   ), S(D,"U",0.60,5), S(X,"D",0),
    S(D,"D",0.75), S(D,"U",0.55), S(X,"D",0     ), S(D,"U",0.50,5),
  }},

  -- ── FOLK / COUNTRY ────────────────────────────────────────
  {name="Folk Waltz 3/4",     genre="Folk",    bars=1, timesig={3,4}, subdivisions=6, steps={
    S(D,"D",1.00), S(X,"U",0), S(D,"U",0.60),
    S(D,"D",0.80), S(X,"D",0), S(D,"U",0.65),
  }},
  {name="Country 2-Step",     genre="Folk",    bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00), S(X,"U",0   ), S(D,"D",0.80), S(D,"U",0.65),
    S(D,"D",0.90), S(D,"U",0.60), S(D,"D",0.85), S(D,"U",0.55),
  }},
  {name="Country Boom-Chuck", genre="Folk",    bars=1, timesig={4,4}, subdivisions=4, steps={
    S(D,"D",1.00), S(D,"U",0.70), S(D,"D",0.90), S(D,"U",0.65),
  }},
  {name="Bluegrass Flatpick", genre="Folk",    bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00), S(D,"D",0.75), S(D,"D",0.85), S(D,"U",0.60),
    S(D,"D",0.90), S(D,"D",0.70), S(D,"U",0.65), S(D,"D",0.80),
  }},

  -- ── REGGAE / SKA ──────────────────────────────────────────
  {name="Reggae Skank 4/4",   genre="Reggae",  bars=1, timesig={4,4}, subdivisions=8, steps={
    S(X,"U",0), S(D,"U",0.90,0,"Mut"), S(X,"D",0), S(D,"U",0.85,0,"Mut"),
    S(X,"U",0), S(D,"U",0.90,0,"Mut"), S(X,"D",0), S(D,"U",0.85,0,"Mut"),
  }},
  {name="Ska Upstroke",       genre="Reggae",  bars=1, timesig={4,4}, subdivisions=8, steps={
    S(X,"U",0), S(D,"U",0.95), S(X,"D",0   ), S(D,"U",0.90),
    S(X,"U",0), S(D,"U",0.95), S(D,"D",0.60), S(D,"U",0.85),
  }},

  -- ── BLUES ────────────────────────────────────────────────
  {name="Blues Shuffle",      genre="Blues",   bars=1, timesig={4,4}, subdivisions=12, steps={
    S(D,"D",1.00,0), S(X,"U",0), S(D,"U",0.65,4),
    S(D,"D",0.85,0), S(X,"U",0), S(D,"U",0.60,4),
    S(D,"D",0.90,0), S(X,"U",0), S(D,"U",0.65,4),
    S(D,"D",0.80,0), S(X,"U",0), S(D,"U",0.60,4),
  }},
  {name="Blues 12bar Feel",   genre="Blues",   bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00), S(X,"U",0   ), S(D,"D",0.75), S(D,"U",0.65),
    S(D,"D",0.85), S(D,"U",0.60), S(X,"D",0   ), S(D,"U",0.55),
  }},

  -- ── FUNK ─────────────────────────────────────────────────
  {name="Funk 16th Groove",   genre="Funk",    bars=1, timesig={4,4}, subdivisions=16, steps={
    S(D,"D",1.00,0,"Mut"), S(X,"U",0         ), S(D,"U",0.60,0,"Mut"), S(X,"D",0),
    S(D,"D",0.85,0,"Mut"), S(D,"U",0.55      ), S(X,"D",0            ), S(D,"U",0.65,0,"Mut"),
    S(D,"D",0.90,0,"Mut"), S(X,"U",0         ), S(D,"U",0.60,0,"Mut"), S(D,"D",0.70),
    S(X,"D",0            ), S(D,"U",0.65,0,"Mut"), S(D,"D",0.80,0,"Mut"), S(X,"U",0),
  }},
  {name="Funk Clav 4/4",      genre="Funk",    bars=1, timesig={4,4}, subdivisions=16, steps={
    S(D,"D",1.00), S(X,"U",0   ), S(X,"D",0   ), S(D,"U",0.70),
    S(X,"D",0   ), S(D,"D",0.85), S(D,"U",0.60), S(X,"D",0   ),
    S(D,"D",0.95), S(X,"U",0   ), S(D,"U",0.65), S(X,"D",0   ),
    S(X,"D",0   ), S(D,"D",0.80), S(X,"U",0   ), S(D,"U",0.60),
  }},

  -- ── LATIN ────────────────────────────────────────────────
  {name="Samba 2bar",         genre="Latin",   bars=2, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00), S(D,"U",0.60), S(D,"D",0.85), S(X,"U",0   ),
    S(D,"U",0.65), S(D,"D",0.80), S(X,"U",0   ), S(D,"U",0.55),
    S(D,"D",0.90), S(D,"U",0.60), S(X,"D",0   ), S(D,"D",0.80),
    S(D,"U",0.65), S(X,"D",0   ), S(D,"D",0.85), S(D,"U",0.60),
  }},
  {name="Cumbia 4/4",         genre="Latin",   bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00), S(X,"U",0   ), S(D,"D",0.85), S(D,"U",0.60),
    S(X,"D",0   ), S(D,"D",0.90), S(D,"U",0.55), S(X,"D",0   ),
  }},

  -- ── FLAMENCO / WORLD ──────────────────────────────────────
  {name="Flamenco Buleria",   genre="World",   bars=1, timesig={12,8}, subdivisions=12, steps={
    S(D,"D",1.00), S(X,"U",0   ), S(D,"D",0.70),
    S(X,"D",0   ), S(D,"D",0.85), S(X,"U",0   ),
    S(D,"D",0.75), S(X,"D",0   ), S(D,"D",0.90),
    S(X,"U",0   ), S(D,"D",0.80), S(X,"U",0   ),
  }},
  {name="Flamenco Rumba",     genre="World",   bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",1.00), S(D,"U",0.70), S(D,"D",0.80), S(D,"U",0.65),
    S(D,"D",0.90,0,"Slp"), S(D,"U",0.60), S(D,"D",0.85), S(D,"U",0.55),
  }},

  -- ── HARMONIC showcase ─────────────────────────────────────
  {name="Harp Harmonics",     genre="World",   bars=1, timesig={4,4}, subdivisions=8, steps={
    S(D,"D",0.75,0,"Hrm"), S(X,"U",0            ), S(D,"D",0.65,0,"Hrm"), S(X,"U",0),
    S(D,"D",0.70,0,"Hrm"), S(D,"D",0.60,0,"Hrm"), S(X,"U",0            ), S(D,"D",0.65,0,"Hrm"),
  }},
}

-- ============================================================
-- §4  Utilities
-- ============================================================
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end

local function deep_copy_pattern(p)
  local n = {name=p.name, genre=p.genre, bars=p.bars,
             timesig={p.timesig[1],p.timesig[2]},
             subdivisions=p.subdivisions, steps={}}
  for i,s in ipairs(p.steps) do
    n.steps[i]={on=s.on,dir=s.dir,vel=s.vel,offset=s.offset,tech=s.tech,span=s.span or 1}
  end
  return n
end

-- ============================================================
-- §5  Minimal JSON parser
-- ============================================================
local json = {}

local function json_skip(s,i)
  while i<=#s and s:sub(i,i):match("%s") do i=i+1 end
  return i
end

local function json_val(s,i)
  i=json_skip(s,i)
  local c=s:sub(i,i)
  if c=='"' then
    local j,r=i+1,""
    while j<=#s do
      local cc=s:sub(j,j)
      if cc=='"' then return r,j+1 end
      if cc=='\\' then
        local ec=s:sub(j+1,j+1)
        local esc={n="\n",t="\t",r="\r",['"']='"',['\\']='\\'}
        r=r..(esc[ec] or ec); j=j+2
      else r=r..cc; j=j+1 end
    end
    return r,j
  elseif c=='{' then
    local obj={}; i=i+1; i=json_skip(s,i)
    if s:sub(i,i)=='}' then return obj,i+1 end
    while true do
      i=json_skip(s,i)
      local k,ni=json_val(s,i); i=ni
      i=json_skip(s,i); i=i+1  -- skip ':'
      i=json_skip(s,i)
      local v; v,i=json_val(s,i)
      obj[k]=v
      i=json_skip(s,i)
      if s:sub(i,i)=='}' then return obj,i+1 end
      i=i+1
    end
  elseif c=='[' then
    local arr={}; i=i+1; i=json_skip(s,i)
    if s:sub(i,i)==']' then return arr,i+1 end
    while true do
      i=json_skip(s,i)
      local v; v,i=json_val(s,i)
      table.insert(arr,v)
      i=json_skip(s,i)
      if s:sub(i,i)==']' then return arr,i+1 end
      i=i+1
    end
  elseif s:sub(i,i+3)=="true"  then return true,i+4
  elseif s:sub(i,i+4)=="false" then return false,i+5
  elseif s:sub(i,i+3)=="null"  then return nil,i+4
  else
    local num,j=s:match("^(-?%d+%.?%d*[eE]?[+-]?%d*)()",i)
    if num then return tonumber(num),j end
    return nil,i+1
  end
end

function json.decode(s)
  local ok,v=pcall(function() local r,_=json_val(s,1); return r end)
  return ok and v or nil
end

function json.encode_pattern(pat)
  local lines = {
    '{',
    string.format('  "name": "%s",', pat.name),
    string.format('  "genre": "%s",', pat.genre),
    string.format('  "bars": %d,', pat.bars),
    string.format('  "timesig": [%d, %d],', pat.timesig[1], pat.timesig[2]),
    string.format('  "subdivisions": %d,', pat.subdivisions),
    '  "steps": [',
  }
  local tech_long={Nrm="normal",Mut="mute",Hrm="harmonic",Slp="slap"}
  for i,s in ipairs(pat.steps) do
    local comma = i<#pat.steps and "," or ""
    table.insert(lines, string.format(
      '    {"on":%s,"dir":"%s","vel":%.2f,"offset":%d,"tech":"%s","span":%d}%s',
      s.on and "true" or "false", s.dir, s.vel, s.offset,
      tech_long[s.tech] or "normal", s.span or 1, comma))
  end
  table.insert(lines, '  ]')
  table.insert(lines, '}')
  return table.concat(lines,"\n")
end

-- ============================================================

-- ============================================================
-- Persistence  (auto-save / auto-load)
-- ============================================================
-- Save file: <Reaper resource dir>/Scripts/Strummer_userdata.json
local SAVE_PATH = reaper.GetResourcePath():gsub("\\","/") .. "/Scripts/Strummer_userdata.json"

local function encode_userdata(ui_state, user_patterns)
  local tech_long={Nrm="normal",Mut="mute",Hrm="harmonic",Slp="slap"}
  local out={}
  local function w(s) table.insert(out,s) end
  w('{')
  w(string.format('  "settings":{"mode":"%s","chord_type_idx":%d,"humanize_time":%d,"humanize_vel":%d,"strum_speed":%d},',
    ui_state.mode,ui_state.chord_type_idx,ui_state.humanize_time,ui_state.humanize_vel,ui_state.strum_speed))
  w('  "tech_map":{')
  local techs={"Nrm","Mut","Hrm","Slp"}
  for ti,tk in ipairs(techs) do
    local m=ui_state.tech_map[tk]
    local c=ti<#techs and "," or ""
    w(string.format('    "%s":{"type":"%s","chan":%d,"note":%d,"cc_num":%d,"cc_val":%d,"pre_ticks":%d}%s',
      tk,m.type or "none",m.chan or 0,m.note or 0,m.cc_num or 64,m.cc_val or 127,m.pre_ticks or 4,c))
  end
  w('  },')
  w('  "user_patterns":[')
  for pi,pat in ipairs(user_patterns) do
    local pc=pi<#user_patterns and "," or ""
    w('    {')
    w(string.format('      "name":"%s","genre":"%s","bars":%d,',pat.name,pat.genre,pat.bars))
    w(string.format('      "timesig":[%d,%d],"subdivisions":%d,',pat.timesig[1],pat.timesig[2],pat.subdivisions))
    w('      "steps":[')
    for si,s in ipairs(pat.steps) do
      local sc=si<#pat.steps and "," or ""
      w(string.format('        {"on":%s,"dir":"%s","vel":%.2f,"offset":%d,"tech":"%s","span":%d}%s',
        s.on and "true" or "false",s.dir,s.vel,s.offset,tech_long[s.tech] or "normal",s.span or 1,sc))
    end
    w('      ]')
    w('    }'..pc)
  end
  w('  ]')
  w('}')
  return table.concat(out,"\n")
end

local function save_userdata(ui_state, user_patterns)
  local f=io.open(SAVE_PATH,"w")
  if not f then return false,"Cannot write: "..SAVE_PATH end
  f:write(encode_userdata(ui_state,user_patterns)); f:close()
  return true,nil
end

local function load_userdata_file()
  local f=io.open(SAVE_PATH,"r")
  if not f then return nil end
  local txt=f:read("*a"); f:close()
  return json.decode(txt)
end

local function apply_userdata(data, ui_state)
  if type(data)~="table" then return {} end
  local s=data.settings
  if type(s)=="table" then
    if s.mode=="chord" or s.mode=="guitar" then ui_state.mode=s.mode end
    if s.chord_type_idx then ui_state.chord_type_idx=math.max(1,math.floor(s.chord_type_idx)) end
    if s.humanize_time  then ui_state.humanize_time =math.floor(s.humanize_time)  end
    if s.humanize_vel   then ui_state.humanize_vel  =math.floor(s.humanize_vel)   end
    if s.strum_speed    then ui_state.strum_speed   =math.floor(s.strum_speed)    end
  end
  local tm=data.tech_map
  if type(tm)=="table" then
    for _,tk in ipairs({"Nrm","Mut","Hrm","Slp"}) do
      local m=tm[tk]
      if type(m)=="table" then
        local dst=ui_state.tech_map[tk]
        dst.type=m.type or "none"
        dst.chan=math.floor(m.chan or 0); dst.note=math.floor(m.note or 0)
        dst.cc_num=math.floor(m.cc_num or 64); dst.cc_val=math.floor(m.cc_val or 127)
        dst.pre_ticks=math.floor(m.pre_ticks or 4)
      end
    end
    -- refresh ks_note_buf after loading
    for _,t in ipairs({"Nrm","Mut","Hrm","Slp"}) do
      local m2=ui_state.tech_map[t]
      ui_state.ks_note_buf[t]=(m2 and m2.note) and midi_to_name(m2.note) or ""
    end
  end
  local result={}
  local TFL={normal="Nrm",mute="Mut",harmonic="Hrm",slap="Slp"}
  if type(data.user_patterns)=="table" then
    for _,p in ipairs(data.user_patterns) do
      if type(p)=="table" and type(p.steps)=="table" and #p.steps>0 then
        local pat={
          name=p.name or "Loaded", genre=p.genre or "Custom",
          bars=math.floor(p.bars or 1),
          timesig={math.floor(((p.timesig or {})[1]) or 4),
                   math.floor(((p.timesig or {})[2]) or 4)},
          subdivisions=math.floor(p.subdivisions or 8), steps={},
        }
        for _,st in ipairs(p.steps) do
          table.insert(pat.steps,{
            on=(st.on~=false), dir=(st.dir=="U" and "U" or "D"),
            vel=clamp(tonumber(st.vel) or 0.8,0,1),
            offset=clamp(math.floor(tonumber(st.offset) or 0),-20,20),
            tech=TFL[st.tech] or "Nrm",
            span=math.max(1,math.floor(tonumber(st.span) or 1)),
          })
        end
        table.insert(result,pat)
      end
    end
  end
  return result
end

-- §6  Import functions
-- ============================================================
local TECH_FROM_LONG = {
  normal="Nrm", mute="Mut", harmonic="Hrm", slap="Slp",
  nrm="Nrm", mut="Mut", hrm="Hrm", slp="Slp",
  NORMAL="Nrm", MUTE="Mut", HARMONIC="Hrm", SLAP="Slp",
  NRM="Nrm", MUT="Mut", HRM="Hrm", SLP="Slp",
}

local function import_json(text)
  local obj=json.decode(text)
  if type(obj)~="table" then return nil,"JSON parse failed" end
  local pat={
    name=obj.name or "JSON Import",
    genre=obj.genre or "Custom",
    bars=obj.bars or 1,
    timesig={4,4},
    subdivisions=obj.subdivisions or 8,
    steps={},
  }
  if type(obj.timesig)=="table" then
    pat.timesig={obj.timesig[1] or 4, obj.timesig[2] or 4}
  end
  if type(obj.steps)~="table" or #obj.steps==0 then
    return nil,"steps field is empty"
  end
  for _,s in ipairs(obj.steps) do
    local dir=(s.dir=="U") and "U" or "D"
    table.insert(pat.steps,{
      on=(s.on~=false), dir=dir,
      vel=clamp(tonumber(s.vel) or 0.8,0,1),
      offset=clamp(tonumber(s.offset) or 0,-20,20),
      tech=TECH_FROM_LONG[s.tech] or "Nrm",
      span=math.max(1,math.floor(tonumber(s.span) or 1)),
    })
  end
  return pat,nil
end

local function import_text(text)
  local pat={name="Text Import",genre="Custom",bars=1,timesig={4,4},subdivisions=8,steps={}}
  for line in (text.."\n"):gmatch("[^\n]+") do
    line=line:match("^%s*(.-)%s*$")
    if line~="" then
      if line:sub(1,1)=="#" then
        local k,v=line:match("^#%s*(%w+)%s*:%s*(.+)$")
        if k and v then
          if     k=="name"         then pat.name=v
          elseif k=="genre"        then pat.genre=v
          elseif k=="bars"         then pat.bars=tonumber(v) or 1
          elseif k=="subdivisions" then pat.subdivisions=tonumber(v) or 8
          elseif k=="timesig"      then
            local a,b=v:match("(%d+)/(%d+)")
            if a then pat.timesig={tonumber(a),tonumber(b)} end
          end
        end
      elseif line:sub(1,1)~="-" or line:find(",") then
        local parts={}
        for p in line:gmatch("[^,]+") do
          table.insert(parts,(p:match("^%s*(.-)%s*$")))
        end
        if #parts>=1 then
          local dr=(parts[1] or "D"):upper()
          local on=(dr=="D" or dr=="U")
          table.insert(pat.steps,{
            on=on, dir=(on and dr or "D"),
            vel=clamp(tonumber(parts[2]) or 0.8,0,1),
            offset=clamp(tonumber(parts[3]) or 0,-20,20),
            tech=TECH_FROM_LONG[parts[4] or "Nrm"] or "Nrm",
            span=math.max(1,math.floor(tonumber(parts[5]) or 1)),
          })
        end
      end
    end
  end
  if #pat.steps==0 then return nil,"No valid step rows found" end
  return pat,nil
end

local function auto_import(text)
  text=text:match("^%s*(.-)%s*$")
  if text:sub(1,1)=="{" then return import_json(text) end
  -- .agr is Ableton's proprietary binary groove format - not parseable in Lua
  if text:lower():find("%.agr") then
    return nil,
      ".agr is Ableton's proprietary binary format and cannot be read directly in Lua.\n"
      .."Recommended workflow: In Ableton, drag the Groove back onto a MIDI clip,\n"
      .."then export as MIDI. Use a MIDI-to-JSON tool (e.g. midi2json) and paste the JSON here."
  end
  return import_text(text)
end

local function export_text(pat)
  local tech_long={Nrm="normal",Mut="mute",Hrm="harmonic",Slp="slap"}
  local lines={
    "# name: "..pat.name,
    "# genre: "..pat.genre,
    "# bars: "..pat.bars,
    "# timesig: "..pat.timesig[1].."/"..pat.timesig[2],
    "# subdivisions: "..pat.subdivisions,
    "# ---",
  }
  for _,s in ipairs(pat.steps) do
    local dir=s.on and s.dir or "-"
    table.insert(lines,string.format("%s,%.2f,%d,%s,%d",
      dir,s.vel,s.offset,tech_long[s.tech] or "normal",s.span or 1))
  end
  return table.concat(lines,"\n")
end

-- ============================================================
-- §7  Guitar chord voicing
-- ============================================================
local function map_to_guitar(input_notes, chord_type_idx)
  if #input_notes==0 then return {} end
  local notes={}
  if #input_notes==1 then
    local root=input_notes[1]
    local ct=CHORD_TYPES[chord_type_idx] or CHORD_TYPES[1]
    for _,iv in ipairs(ct.intervals) do table.insert(notes,root+iv) end
  else
    for _,n in ipairs(input_notes) do table.insert(notes,n) end
  end
  table.sort(notes)

  local root=notes[1]
  local ivset,seen={},{}
  for _,n in ipairs(notes) do
    local iv=(n-root)%12
    if not seen[iv] then seen[iv]=true; table.insert(ivset,iv) end
  end

  local rsi,radj=nil,root
  for _,si in ipairs({1,2,3}) do
    local open=GUITAR_STRINGS[si]
    for oct=-2,2 do
      local c=root+oct*12
      if c-open>=0 and c-open<=15 then rsi=si; radj=c; break end
    end
    if rsi then break end
  end
  if not rsi then
    local out={}
    for _,n in ipairs(notes) do
      local c=n
      while c<40 do c=c+12 end; while c>88 do c=c-12 end
      table.insert(out,c); if #out>=6 then break end
    end
    return out
  end

  local result={radj}
  for si=rsi+1,#GUITAR_STRINGS do
    local open=GUITAR_STRINGS[si]
    local best,bsc=nil,9999
    for _,iv in ipairs(ivset) do
      for oct=-1,2 do
        local c=radj+iv+oct*12
        local fret=c-open
        if fret>=0 and fret<=15 then
          local sc=math.abs(fret-5)+math.abs(c-result[#result])*0.1
          if sc<bsc then bsc=sc; best=c end
        end
      end
    end
    if best then table.insert(result,best) end
    if #result>=6 then break end
  end
  return result
end

-- ============================================================
-- §8  MIDI gather
-- ============================================================
local function gather_chords(take)
  local _,nc,_,_=reaper.MIDI_CountEvts(take)
  if nc==0 then return {} end
  local raw={}
  for i=0,nc-1 do
    local ok,_,_,sp,ep,_,pitch,vel=reaper.MIDI_GetNote(take,i)
    if ok then table.insert(raw,{start=sp,endp=ep,pitch=pitch,vel=vel}) end
  end
  table.sort(raw,function(a,b) return a.start<b.start end)
  local chords,tol={},10
  for _,n in ipairs(raw) do
    local placed=false
    for _,c in ipairs(chords) do
      if math.abs(c.startppq-n.start)<=tol then
        table.insert(c.notes,n.pitch)
        c.vel=math.max(c.vel,n.vel)
        if n.endp>c.endppq then c.endppq=n.endp end
        placed=true; break
      end
    end
    if not placed then
      table.insert(chords,{startppq=n.start,endppq=n.endp,notes={n.pitch},vel=n.vel})
    end
  end
  return chords
end

-- ============================================================
-- §9  Strum engine
-- ============================================================
local function apply_strummer(take, chords, pattern, settings, tech_map)
  local _,nc,_,_=reaper.MIDI_CountEvts(take)
  for i=nc-1,0,-1 do reaper.MIDI_DeleteNote(take,i) end

  local ppq=960
  -- step_ppq: always based on quarter=960, subdivisions decides the grid.
  -- timesig[1] is metadata only and must not affect timing.
  local step_ppq=(ppq*4)/pattern.subdivisions

  for ci,chord in ipairs(chords) do
    local cnotes
    if settings.mode=="guitar" then
      cnotes=map_to_guitar(chord.notes,settings.chord_type_idx)
    else
      cnotes={}; for _,p in ipairs(chord.notes) do table.insert(cnotes,p) end
    end
    table.sort(cnotes)
    if #cnotes==0 then goto cont end

    local chord_end=chord.endppq
    if ci<#chords then chord_end=chords[ci+1].startppq end
    local chord_dur=chord_end-chord.startppq
    -- Pattern real length = sum of all step spans * step_ppq
    local pat_total_span=0
    for _,st in ipairs(pattern.steps) do
      pat_total_span=pat_total_span+(st.span or 1)
    end
    local pat_ppq=pat_total_span*step_ppq
    local total_bars=math.max(1,math.floor(chord_dur/pat_ppq+0.5))

    for bar=0,total_bars-1 do
      -- Pre-compute each step's start offset by accumulating spans
      local step_offsets={}
      local acc=0
      for _,st in ipairs(pattern.steps) do
        table.insert(step_offsets, acc*step_ppq)
        acc=acc+(st.span or 1)
      end

      for si,step in ipairs(pattern.steps) do
        if not step.on then goto skip end
        local step_start=chord.startppq+bar*pat_ppq+step_offsets[si]
        if step_start>=chord_end then goto done end

        local ht=math.random(-settings.humanize_time,settings.humanize_time)
        local t0=step_start+step.offset+ht

        -- direction sort
        local ordered={}
        for _,p in ipairs(cnotes) do table.insert(ordered,p) end
        if step.dir=="U" then
          local rev={}
          for i2=#ordered,1,-1 do table.insert(rev,ordered[i2]) end
          ordered=rev
        end

        -- note duration = span * step_ppq, adjusted per technique
        local span_ppq=(step.span or 1)*step_ppq
        local nd=span_ppq-20
        if step.tech=="Mut" then nd=math.floor(span_ppq*0.22) end
        if step.tech=="Hrm" then nd=math.floor(span_ppq*0.92) end
        if step.tech=="Slp" then nd=math.floor(span_ppq*0.12) end

        -- send KeySwitch / CC before notes
        local tm=tech_map and tech_map[step.tech]
        if tm then
          local pre=tm.pre_ticks or 4
          if tm.type=="ks_note" and tm.note then
            local ks_t=math.max(0,math.floor(t0)-pre)
            reaper.MIDI_InsertNote(take,false,false,
              ks_t,ks_t+8, tm.chan or 0, tm.note, 64, false)
          elseif tm.type=="cc" and tm.cc_num then
            local cc_t=math.max(0,math.floor(t0)-pre)
            reaper.MIDI_InsertCC(take,false,false,
              cc_t, 0xB0, tm.chan or 0, tm.cc_num, tm.cc_val or 127)
          end
        end

        -- insert strum notes
        for ni,pitch in ipairs(ordered) do
          local nt=t0+(ni-1)*settings.strum_speed
          local hv=math.random(-settings.humanize_vel,settings.humanize_vel)
          local vel=clamp(math.floor(chord.vel*step.vel)+hv,1,127)
          if step.tech=="Hrm" then vel=math.floor(vel*0.65) end
          reaper.MIDI_InsertNote(take,false,false,
            math.floor(nt),math.floor(nt+nd),0,pitch,vel,false)
        end
        ::skip::
      end
      ::done::
    end
    ::cont::
  end
  reaper.MIDI_Sort(take)
end

-- ============================================================
-- §10  GUI state
-- ============================================================
local ui={
  pattern        = deep_copy_pattern(PATTERN_LIBRARY[1]),
  lib_idx        = 1,
  user_patterns  = {},   -- user-saved patterns (persisted to disk)
  mode           = "chord",
  chord_type_idx = 1,
  humanize_time  = 8,
  humanize_vel   = 12,
  strum_speed    = 4,
  selected_step  = 0,
  lib_src        = "builtin", -- "builtin" | "user"
  show_library   = true,
  show_import    = false,
  show_ks        = false,
  filter_genre   = "All",
  import_buf     = "",
  import_msg     = "",
  status_msg     = "Ready.",
  status_ok      = true,
  tech_map       = copy_tech_map(TECH_MAP_DEFAULT),
  ks_note_buf    = {},
}
for _,t in ipairs(TECHNIQUES) do
  local m=ui.tech_map[t]
  ui.ks_note_buf[t]=(m and m.note) and midi_to_name(m.note) or ""
end

-- Auto-load saved userdata on startup
do
  local data=load_userdata_file()
  if data then
    ui.user_patterns=apply_userdata(data,ui)
    if #ui.user_patterns>0 then
      ui.status_msg=string.format("Loaded %d user pattern(s) from disk.",#ui.user_patterns)
    end
  end
end

-- Auto-save on exit
reaper.atexit(function()
  save_userdata(ui, ui.user_patterns)
end)

local function get_genres()
  local g={"All","[User]"}; local seen={All=true,["[User]"]=true}
  for _,p in ipairs(PATTERN_LIBRARY) do
    if not seen[p.genre] then seen[p.genre]=true; table.insert(g,p.genre) end
  end
  for _,p in ipairs(ui.user_patterns) do
    if not seen[p.genre] then seen[p.genre]=true; table.insert(g,p.genre) end
  end
  return g
end
-- GENRES is rebuilt each frame in draw_library so user genres appear dynamically

-- ============================================================
-- §11  GUI rendering
-- ============================================================
local ctx=reaper.ImGui_CreateContext(SCRIPT_NAME)
local WIN_FLAGS=reaper.ImGui_WindowFlags_AlwaysAutoResize()
local DIR_COL={D=0x42A5F5FF, U=0xFF7043FF}
local OFF_COL=0x2C2C2C88
local SEL_COL=0xFFD700FF

-- Pattern grid
local function draw_grid()
  local pat=ui.pattern; local steps=pat.steps
  local CW,CH=46,60

  reaper.ImGui_Text(ctx, pat.name.."  ["
    ..pat.timesig[1].."/"..pat.timesig[2].."  "..#steps.." steps]")

  -- Global step unit selector
  -- subdivisions = how many steps fit in one bar
  -- For 4/4: 4=quarter, 8=eighth, 16=sixteenth, 32=32nd
  -- We express this as "beats * (note_denom/beat_denom)"
  -- subdivisions = number of equal steps per bar
  -- step_ppq = bar_ppq / subdivisions
  -- In 4/4: sub=4 -> quarter(960t), sub=8 -> 8th(480t), sub=16 -> 16th(240t), sub=32 -> 32nd(120t)
  local unit_opts={
    {label="1/1",  sub=1 },
    {label="1/2",  sub=2 },
    {label="1/4",  sub=4 },
    {label="1/8",  sub=8 },
    {label="1/16", sub=16},
    {label="1/32", sub=32},
    {label="1/3",  sub=3 },   -- quarter triplet
    {label="1/6",  sub=6 },   -- 8th triplet
    {label="1/12", sub=12},   -- 16th triplet
  }
  reaper.ImGui_Text(ctx,"Step unit:")
  reaper.ImGui_SetItemTooltip(ctx,"The duration of each grid cell.\n1/16 = sixteenth note per step, 1/8 = eighth note, etc.\nUse smaller values to represent faster rhythms.")
  for _,opt in ipairs(unit_opts) do
    reaper.ImGui_SameLine(ctx)
    local active=(pat.subdivisions==opt.sub)
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),
      active and 0x7B5EA7FF or 0x44444488)
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_ButtonHovered(),
      active and 0x9B7EC7FF or 0x55555599)
    if reaper.ImGui_Button(ctx,opt.label.."##su"..opt.sub) then
      pat.subdivisions=opt.sub
    end
    reaper.ImGui_PopStyleColor(ctx,2)
    reaper.ImGui_SetItemTooltip(ctx,string.format("Set step unit to %s note.\n(subdivisions=%d)", opt.label, opt.sub))
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx," custom:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx,50)
  local rsub,vsub=reaper.ImGui_InputInt(ctx,"##subcustom",pat.subdivisions)
  if rsub then pat.subdivisions=math.max(1,vsub) end
  reaper.ImGui_SetItemTooltip(ctx,"Enter a custom subdivisions value.\nE.g. 12 for 16th note triplets in 4/4, 24 for 32nd triplets.")

  reaper.ImGui_Separator(ctx)

  for i,step in ipairs(steps) do
    reaper.ImGui_PushID(ctx,i)
    local bg=OFF_COL
    if step.on then bg=DIR_COL[step.dir] or DIR_COL.D end
    if ui.selected_step==i then bg=SEL_COL end

    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),bg)
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_ButtonHovered(),bg)

    -- Button width scales with span
    local sp=step.span or 1
    local bw=CW*sp+(sp-1)*4

    local lbl
    if step.on then
      lbl = (step.dir=="D" and "v" or "^")
            .."\n"..string.format("%d%%",math.floor(step.vel*100))
            .."\n"..step.tech..(sp>1 and " x"..sp or "")
    else
      lbl = "X\n--\n"..(sp>1 and "x"..sp or "---")
    end

    if reaper.ImGui_Button(ctx,lbl,bw,CH) then
      ui.selected_step=(ui.selected_step==i) and 0 or i
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      local tip=string.format("Step %d\n%s  vel=%.0f%%  offset=%d ticks  %s  span=x%d\n"
        .."Left-click: select and edit  Right-click: toggle on/off",
        i, step.on and (step.dir=="D" and "Down strum" or "Up strum") or "Silent",
        (step.vel or 0)*100, step.offset or 0, TECH_FULL[step.tech] or step.tech, step.span or 1)
      reaper.ImGui_SetItemTooltip(ctx,tip)
    end
    if reaper.ImGui_IsItemClicked(ctx,1) then step.on=not step.on end

    reaper.ImGui_PopStyleColor(ctx,2)
    if i<#steps then reaper.ImGui_SameLine(ctx) end
    reaper.ImGui_PopID(ctx)
  end

  -- + / - buttons to add/remove steps
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_BeginGroup(ctx)
  if reaper.ImGui_Button(ctx,"+##add",24,28) and #steps<32 then
    table.insert(steps,{on=true,dir="D",vel=0.8,offset=0,tech="Nrm",span=1})
  end
  if reaper.ImGui_Button(ctx,"-##rem",24,28) and #steps>1 then
    if ui.selected_step==#steps then ui.selected_step=0 end
    table.remove(steps)
  end
  reaper.ImGui_EndGroup(ctx)

  reaper.ImGui_Separator(ctx)

  -- Selected step detail editor
  if ui.selected_step>0 and steps[ui.selected_step] then
    local s=steps[ui.selected_step]
    reaper.ImGui_Text(ctx,"Edit Step "..ui.selected_step)
    local rv,nv=reaper.ImGui_Checkbox(ctx,"On##son",s.on)
    if rv then s.on=nv end
    reaper.ImGui_SetItemTooltip(ctx,"Enable or disable this step.\nDisabled steps are silent (no strum).")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx,"Down (v)",s.dir=="D") then s.dir="D";s.on=true end
    reaper.ImGui_SetItemTooltip(ctx,"Down strum: plays strings from lowest to highest pitch.")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx,"Up  (^)",s.dir=="U")  then s.dir="U";s.on=true end
    reaper.ImGui_SetItemTooltip(ctx,"Up strum: plays strings from highest to lowest pitch.")

    reaper.ImGui_SetNextItemWidth(ctx,220)
    local r2,v2=reaper.ImGui_SliderDouble(ctx,"Velocity##sv",s.vel,0,1,"%.2f")
    if r2 then s.vel=v2 end
    reaper.ImGui_SetItemTooltip(ctx,"Velocity scale for this step (0=silent, 1=full).\nMultiplied by the source chord velocity.")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx,160)
    local r3,v3=reaper.ImGui_SliderInt(ctx,"Offset ticks##so",s.offset,-20,20)
    if r3 then s.offset=v3 end
    reaper.ImGui_SetItemTooltip(ctx,"Shift this step earlier (negative) or later (positive).\nUseful for swing feel or grace notes.\nApplied before humanization.")

    reaper.ImGui_Text(ctx,"Technique: ")
    for _,tech in ipairs(TECHNIQUES) do
      reaper.ImGui_SameLine(ctx)
      local tc=TECH_COLORS[tech] or 0xFFFFFFFF
      reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),
        s.tech==tech and tc or 0x44444488)
      reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_ButtonHovered(),
        s.tech==tech and tc or 0x55555599)
      if reaper.ImGui_Button(ctx,TECH_FULL[tech].."##t"..tech) then s.tech=tech end
      reaper.ImGui_PopStyleColor(ctx,2)
    end

    -- Per-step span: multiplier of the global step unit
    local cur_sp=s.span or 1
    reaper.ImGui_Text(ctx,"Step span (x base unit):")
    reaper.ImGui_SetItemTooltip(ctx,"How many base grid units this step occupies.\nx2 = twice the base duration, etc.\nUseful for mixed note values within one pattern.")
    for _,sv in ipairs({1,2,3,4,6,8}) do
      reaper.ImGui_SameLine(ctx)
      local active=(cur_sp==sv)
      reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),
        active and 0x7B5EA7FF or 0x44444488)
      reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_ButtonHovered(),
        active and 0x9B7EC7FF or 0x55555599)
      if reaper.ImGui_Button(ctx,"x"..sv.."##sp"..sv) then s.span=sv end
      reaper.ImGui_PopStyleColor(ctx,2)
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx," custom:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx,46)
    local rsp,vsp=reaper.ImGui_InputInt(ctx,"##spfree",cur_sp)
    if rsp then s.span=math.max(1,vsp) end
    reaper.ImGui_SetItemTooltip(ctx,"Enter a custom span value for unusual note lengths\n(e.g. 3 for a dotted note when base unit is 1/8).")
    reaper.ImGui_Separator(ctx)
  end
end

-- Pattern library panel
local function draw_library()
  local genres=get_genres()
  for gi,g in ipairs(genres) do
    if gi>1 then reaper.ImGui_SameLine(ctx) end
    if reaper.ImGui_RadioButton(ctx,g,ui.filter_genre==g) then ui.filter_genre=g end
  end
  reaper.ImGui_Separator(ctx)

  -- Built-in patterns
  local show_all = ui.filter_genre=="All"
  if not (ui.filter_genre=="[User]") then
    for i,p in ipairs(PATTERN_LIBRARY) do
      if show_all or p.genre==ui.filter_genre then
        local lbl=string.format("[%s] %s  %d/%d  %dsteps",
          p.genre,p.name,p.timesig[1],p.timesig[2],#p.steps)
        if reaper.ImGui_Selectable(ctx,lbl,ui.lib_idx==i and ui.lib_src=="builtin") then
          ui.lib_idx=i; ui.lib_src="builtin"
          ui.pattern=deep_copy_pattern(PATTERN_LIBRARY[i])
          ui.selected_step=0
        end
      end
    end
  end

  -- User patterns
  if show_all and #ui.user_patterns>0 then
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx,"-- User Patterns --")
  end
  if show_all or ui.filter_genre=="[User]" then
    local del_idx=nil
    for i,p in ipairs(ui.user_patterns) do
      reaper.ImGui_PushID(ctx,"up"..i)
      -- Del button drawn FIRST so Selectable doesn't overlap it
      if reaper.ImGui_Button(ctx,"Del") then del_idx=i end
      reaper.ImGui_SameLine(ctx)
      local lbl=string.format("%s  %d/%d  %dsteps",
        p.name,p.timesig[1],p.timesig[2],#p.steps)
      if reaper.ImGui_Selectable(ctx,lbl,ui.lib_idx==i and ui.lib_src=="user") then
        ui.lib_idx=i; ui.lib_src="user"
        ui.pattern=deep_copy_pattern(ui.user_patterns[i])
        ui.selected_step=0
      end
      reaper.ImGui_PopID(ctx)
    end
    -- Delete after loop to avoid invalidating indices mid-iteration
    if del_idx then
      table.remove(ui.user_patterns,del_idx)
      save_userdata(ui,ui.user_patterns)
      if ui.lib_src=="user" then
        if ui.lib_idx==del_idx     then ui.lib_src="builtin"; ui.lib_idx=1
        elseif ui.lib_idx>del_idx  then ui.lib_idx=ui.lib_idx-1 end
      end
    end
  end
end

-- Import/Export panel
local function draw_import()
  reaper.ImGui_TextWrapped(ctx,
    "Supported formats:\n"
    .."  JSON: {name,genre,timesig,subdivisions,bars,steps:[{on,dir,vel,offset,tech}]}\n"
    .."  Text: # key:value header lines + D/U/-,vel,offset,tech data lines\n"
    .."  .agr: see note below")
  reaper.ImGui_Separator(ctx)

  local rv,nb=reaper.ImGui_InputTextMultiline(ctx,"##ibuf",ui.import_buf,700,130)
  if rv then ui.import_buf=nb end

  if reaper.ImGui_Button(ctx,"Import##imp") then
    local pat,err=auto_import(ui.import_buf)
    if pat then
      ui.pattern=pat; ui.import_msg="OK: imported '"..pat.name.."'"
      ui.show_import=false
    else
      ui.import_msg="ERR: "..(err or "unknown")
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,"Export JSON -> Clipboard") then
    if reaper.CF_SetClipboard then
      reaper.CF_SetClipboard(json.encode_pattern(ui.pattern))
      ui.import_msg="Copied JSON to clipboard."
    else ui.import_msg="js_ReaScriptAPI needed for CF_SetClipboard." end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,"Export Text -> Clipboard") then
    if reaper.CF_SetClipboard then
      reaper.CF_SetClipboard(export_text(ui.pattern))
      ui.import_msg="Copied Text to clipboard."
    end
  end

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx,"Save current pattern to User Library:")
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,"Save to User Library##saveusr") then
    -- Check for duplicate name
    local dup=false
    for _,p in ipairs(ui.user_patterns) do
      if p.name==ui.pattern.name then dup=true; break end
    end
    if dup then
      ui.import_msg="ERR: A user pattern named '"..ui.pattern.name.."' already exists. Rename it first."
    else
      table.insert(ui.user_patterns, deep_copy_pattern(ui.pattern))
      local ok,err2=save_userdata(ui,ui.user_patterns)
      ui.import_msg=ok and ("Saved '"..ui.pattern.name.."' to user library ("..#ui.user_patterns.." total).")
                        or ("ERR saving: "..(err2 or "?"))
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,"Save All Now##saveall") then
    local ok,err2=save_userdata(ui,ui.user_patterns)
    ui.import_msg=ok and "Saved settings + "..#ui.user_patterns.." user pattern(s) to disk."
                      or "ERR: "..(err2 or "?")
  end
  if ui.import_msg~="" then
    reaper.ImGui_TextWrapped(ctx, ui.import_msg)
  end
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_TextWrapped(ctx,
    "Ableton .agr note: .agr is a proprietary binary groove format and cannot be\n"
    .."read directly in Lua. Recommended: in Ableton drag the groove back onto a\n"
    .."MIDI clip, export as .mid, convert with midi2json, then paste JSON above.")
end

-- KeySwitch / CC mapping panel
local function draw_ks_panel()
  reaper.ImGui_TextWrapped(ctx,
    "Configure KeySwitch notes or CC events per technique.\n"
    .."KS notes are sent on the configured channel a few ticks before the strum.\n"
    .."Ample Sound defaults: Hrm=C-1 (MIDI 0), Slp=D-1 (MIDI 2), Channel=1 (0-indexed=0)")
  reaper.ImGui_Separator(ctx)

  local type_combo = "None\0KS Note\0CC\0"

  for _,tech in ipairs(TECHNIQUES) do
    local m=ui.tech_map[tech]
    reaper.ImGui_PushID(ctx,"ks_"..tech)

    reaper.ImGui_Text(ctx, string.format("%-10s",TECH_FULL[tech]))
    reaper.ImGui_SameLine(ctx)

    local cur=(m.type=="none" and 0) or (m.type=="ks_note" and 1) or
              (m.type=="cc"   and 2) or 0
    reaper.ImGui_SetNextItemWidth(ctx,90)
    local rv,ni=reaper.ImGui_Combo(ctx,"##type",cur,type_combo)
    if rv then
      local ts={"none","ks_note","cc"}; m.type=ts[ni+1]
    end
    reaper.ImGui_SetItemTooltip(ctx,"None: no extra MIDI event.\nKS Note: sends a keyswitch note before the strum.\nCC: sends a Control Change message before the strum.")

    if m.type=="ks_note" then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"Ch:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx,45)
      local r2,cv=reaper.ImGui_InputInt(ctx,"##ch",m.chan or 0)
      if r2 then m.chan=clamp(cv,0,15) end

      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"Note:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx,68)
      local r3,ns=reaper.ImGui_InputText(ctx,"##note",ui.ks_note_buf[tech] or "")
      if r3 then
        ui.ks_note_buf[tech]=ns
        local n=name_to_midi(ns)
        if n then m.note=n end
      end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, string.format("= MIDI %d", m.note or -1))

      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"Pre:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx,50)
      local r4,pv=reaper.ImGui_InputInt(ctx,"##pre",m.pre_ticks or 4)
      if r4 then m.pre_ticks=clamp(pv,0,48) end
      reaper.ImGui_SetItemTooltip(ctx,"How many ticks before the strum to send the KS note.\nMust be enough for your sampler to respond. 4-8 is typical.")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"ticks")

    elseif m.type=="cc" then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"Ch:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx,45)
      local r2,cv=reaper.ImGui_InputInt(ctx,"##cch",m.chan or 0)
      if r2 then m.chan=clamp(cv,0,15) end

      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"CC#:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx,52)
      local r3,cn=reaper.ImGui_InputInt(ctx,"##ccn",m.cc_num or 64)
      if r3 then m.cc_num=clamp(cn,0,127) end

      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"Val:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx,52)
      local r4,cv2=reaper.ImGui_InputInt(ctx,"##ccv",m.cc_val or 127)
      if r4 then m.cc_val=clamp(cv2,0,127) end

      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"Pre:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx,50)
      local r5,pv=reaper.ImGui_InputInt(ctx,"##pre2",m.pre_ticks or 4)
      if r5 then m.pre_ticks=clamp(pv,0,48) end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"ticks")
    end

    reaper.ImGui_PopID(ctx)
  end

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_TextWrapped(ctx,
    "Ample Sound reference:\n"
    .."  Harmonics  -> Channel 1, C-1  (MIDI 0)\n"
    .."  Slap/Slapp -> Channel 1, D-1  (MIDI 2)\n"
    .."  Mute: best achieved by short note duration (already applied), no KS needed")
end

-- Apply button action
local function do_apply()
  local item=reaper.GetSelectedMediaItem(0,0)
  if not item then
    ui.status_msg="ERR: Select a MIDI item first"; ui.status_ok=false; return end
  local take=reaper.GetActiveTake(item)
  if not take or not reaper.TakeIsMIDI(take) then
    ui.status_msg="ERR: Not a MIDI take"; ui.status_ok=false; return end
  local chords=gather_chords(take)
  if #chords==0 then
    ui.status_msg="ERR: No notes found in MIDI item"; ui.status_ok=false; return end

  reaper.Undo_BeginBlock()
  apply_strummer(take,chords,ui.pattern,{
    mode=ui.mode, chord_type_idx=ui.chord_type_idx,
    humanize_time=ui.humanize_time, humanize_vel=ui.humanize_vel,
    strum_speed=ui.strum_speed,
  }, ui.tech_map)
  reaper.UpdateItemInProject(item)
  reaper.Undo_EndBlock("Strummer: Apply pattern",-1)
  ui.status_msg=string.format("OK: Applied to %d chord block(s).",#chords)
  ui.status_ok=true
end

-- ============================================================
-- §12  Main loop
-- ============================================================
local function loop()
  local vis,open=reaper.ImGui_Begin(ctx,SCRIPT_NAME.." v"..VERSION,true,WIN_FLAGS)
  if vis then  -- only draw contents when visible (not collapsed)
    reaper.ImGui_Text(ctx,"Mode: ")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx,"Chord",ui.mode=="chord") then ui.mode="chord" end
    reaper.ImGui_SetItemTooltip(ctx,"Chord mode: notes are passed through exactly as drawn.")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx,"Guitar",ui.mode=="guitar") then ui.mode="guitar" end
    reaper.ImGui_SetItemTooltip(ctx,"Guitar mode: remaps chords to a playable 6-string voicing.\nSingle notes are expanded to full chords using the selected chord type.")
    if ui.mode=="guitar" then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,"  Single note -> chord type:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx,110)
      local combotxt=table.concat((function()
        local t={}; for _,c in ipairs(CHORD_TYPES) do table.insert(t,c.name) end; return t
      end)(),"\0").."\0"
      local rv,ni=reaper.ImGui_Combo(ctx,"##ct",ui.chord_type_idx-1,combotxt)
      if rv then ui.chord_type_idx=ni+1 end
      reaper.ImGui_SetItemTooltip(ctx,"When Guitar mode receives a single note,\nit builds this chord type from that root note.")
    end
    reaper.ImGui_Separator(ctx)

    -- Humanization row
    reaper.ImGui_SetNextItemWidth(ctx,170)
    local r1,v1=reaper.ImGui_SliderInt(ctx,"Time Rand(ticks)##ht",ui.humanize_time,0,30)
    if r1 then ui.humanize_time=v1 end
    reaper.ImGui_SetItemTooltip(ctx,"Random timing offset per note (ticks).\nAdds subtle timing imperfection to simulate a real performance.\nRecommended: 5-12 ticks.")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx,150)
    local r2,v2=reaper.ImGui_SliderInt(ctx,"Vel Rand##hv",ui.humanize_vel,0,30)
    if r2 then ui.humanize_vel=v2 end
    reaper.ImGui_SetItemTooltip(ctx,"Random velocity offset per note.\nMakes each note slightly louder or softer.\nRecommended: 8-15.")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx,160)
    local r3,v3=reaper.ImGui_SliderInt(ctx,"Strum spd(t/str)##ss",ui.strum_speed,1,20)
    if r3 then ui.strum_speed=v3 end
    reaper.ImGui_SetItemTooltip(ctx,"Tick gap between each string in a strum.\nHigher = slower strum arc, more like a gentle sweep.\nLower = faster, more percussive.\nRecommended: 3-8 ticks.")
    reaper.ImGui_Separator(ctx)

    -- Grid
    draw_grid()

    -- Toolbar
    if reaper.ImGui_Button(ctx,"Library##lb") then
      ui.show_library=not ui.show_library; ui.show_import=false; ui.show_ks=false end
    reaper.ImGui_SetItemTooltip(ctx,"Browse and load built-in or user-saved rhythm patterns.")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx,"Import/Export##ie") then
      ui.show_import=not ui.show_import; ui.show_library=false; ui.show_ks=false end
    reaper.ImGui_SetItemTooltip(ctx,"Import patterns from JSON or text format.\nExport current pattern to clipboard.\nSave patterns to your user library.")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx,"KeySwitch/CC##ks") then
      ui.show_ks=not ui.show_ks; ui.show_library=false; ui.show_import=false end
    reaper.ImGui_SetItemTooltip(ctx,"Configure KeySwitch notes or CC messages\nfor each playing technique (Harmonic, Slap, etc).\nAmple Sound defaults: Hrm=C-1, Slp=D-1.")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),        0x2E7D32FF)
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_ButtonHovered(), 0x43A047FF)
    if reaper.ImGui_Button(ctx,"  >> Apply to Selected MIDI <<  ") then do_apply() end
    reaper.ImGui_SetItemTooltip(ctx,"Rewrites the selected MIDI item using the current pattern.\nOriginal notes are deleted and replaced with strummed output.\nThis is one undo step.")
    reaper.ImGui_PopStyleColor(ctx,2)

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextColored(ctx,
      ui.status_ok and 0x80FF80FF or 0xFF8060FF, ui.status_msg)
    reaper.ImGui_End(ctx)   -- ReaImGui: End INSIDE if vis (opposite of Dear ImGui)
  end

  -- Floating panels: same rule, End must be inside the if-visible block
  if ui.show_library then
    reaper.ImGui_SetNextWindowSize(ctx,480,360,reaper.ImGui_Cond_FirstUseEver())
    local lv,lo=reaper.ImGui_Begin(ctx,"Pattern Library##lib",true)
    if lv then draw_library(); reaper.ImGui_End(ctx) end
    if not lo then ui.show_library=false end
  end

  if ui.show_import then
    reaper.ImGui_SetNextWindowSize(ctx,580,340,reaper.ImGui_Cond_FirstUseEver())
    local iv,io2=reaper.ImGui_Begin(ctx,"Import / Export##imp",true)
    if iv then draw_import(); reaper.ImGui_End(ctx) end
    if not io2 then ui.show_import=false end
  end

  if ui.show_ks then
    reaper.ImGui_SetNextWindowSize(ctx,740,300,reaper.ImGui_Cond_FirstUseEver())
    local kv,ko=reaper.ImGui_Begin(ctx,"KeySwitch / CC Mapping##ks",true)
    if kv then draw_ks_panel(); reaper.ImGui_End(ctx) end
    if not ko then ui.show_ks=false end
  end

  if open then reaper.defer(loop) end
end

reaper.defer(loop)
