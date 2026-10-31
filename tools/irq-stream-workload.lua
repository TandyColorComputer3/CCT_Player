-- Explicit experimental streaming capture. The caller mounts isolated media.
-- Requires old pack detached, retained CCTClock link; leaves new pack attached.
return function(commands,array,encode)
 local m=manager.machine;local active=false;local failure=nil
 local function wait(t) assert(emu.wait(t),'discontinuity') end
 local function type(s)
  local deadline=m.time:as_double()+60
  while not m.natkeyboard.empty or m.natkeyboard.is_posting do assert(m.time:as_double()<deadline);wait(.1) end
  commands.type({text=s..'{ENTER}'})
  while not m.natkeyboard.empty or m.natkeyboard.is_posting do assert(m.time:as_double()<deadline);wait(.1) end
  wait(2)
 end
 commands.irq_stream_case=function(p)
  assert(not active and not commands.irq_capture_status().active and not commands.reliability_status().active)
  assert(p.name:match('^[%w_-]+$'))
  active=true;failure=nil
  local thread=coroutine.create(function()
   local ok,err=xpcall(function()
    m.video.throttled=false
    if p.setup then
     type('unlink CCTClock');type('load /d1/streampack');wait(15)
     type('iniz ctclock psgs');wait(3)
     if not p.reload then type('load /d1/cctirq');wait(15) end
    end
    if p.reload then for i=1,(tonumber(p.reload) or 1) do type('unlink cctirq') end;type('load /d1/cctirq');wait(15) end
    local modules=commands.stability_modules({});local resources=commands.irq_resources()
    if p.player_crc then local found=false;for _,mod in ipairs(modules.entries) do if mod.name=='cctirq' then assert(mod.crc==p.player_crc,'player CRC mismatch');found=true end end;assert(found,'player missing') end
    local info=commands.irq_inspect(p.layout);local code=info.base-225;local storage
    for _,e in ipairs(info.polls) do if e.handler==code+156 then storage=e.storage end end
    assert(storage,'clock registration missing')
    if p.concurrent then type(p.concurrent..' &') end
    local prefix='emulator/images/reliability/logs/'..p.name
    local cfg={};for k,v in pairs(p.layout) do cfg[k]=v end
    cfg.duration=p.duration;cfg.path=prefix..'.json';commands.irq_capture(cfg)
    commands.reliability_start({duration=p.duration,interval_us=100,path=prefix..'-clock.json',code=code,storage=storage,input_anchor='psg',inputs=p.inputs})
    commands.reliability_audio({path=prefix..'.wav'});m.video.throttled=not p.fast
    type(p.command..' &')
    local sent=false
    while commands.irq_capture_status().active or commands.reliability_status().active do
     local q=commands.irq_capture_status()
     local anchor=p.signal_anchor=='allocation' and q.first_allocation or q.first_write
     if p.signal and not sent and anchor and m.time:as_double()>=anchor+(p.after or 5) then
      assert(q.producer,'producer not observed')
      local proc=commands.irq_process_info({pid=q.producer})
      assert(proc.live and proc.name=='cctirq' and proc.crc==p.player_crc,'producer identity changed')
      assert(p.signal=='graceful' or p.signal=='kill')
      type((p.signal=='kill' and 'kill ' or 'cctstop ')..q.producer);sent=true
     end
     wait(.1)
    end
    if p.signal then assert(sent,'stop not sent') end
    commands.reliability_audio({});m.video.throttled=false
    type('W');if p.concurrent or p.reap then type('W') end
    commands.snapshot({path=p.name..'.png'})
    local f=assert(io.open(prefix..'-modules.json','w'));f:write(encode({before=modules,after=commands.stability_modules({}),resources_before=resources,resources_after=commands.irq_resources()}));f:close()
   end,debug.traceback)
   if not ok then failure=tostring(err) end
   active=false;m.video.throttled=true
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end

 local series=false;local case_name=nil
 commands.irq_stream_matrix=function(p)
  assert(not series and not active);series=true
  local cases={
   {'vgm-idle','/d1/arkanoid.vgm',35},
   {'counter','/d1/flicky.cct',90,'timeload'},
   {'commands','/d1/flicky.cct',65,nil,{{after=3,text='/dd/cmds/pwd{ENTER}'},{after=8,text='/dd/cmds/mfree{ENTER}'},{after=15,text='echo RESPONSIVE{ENTER}'}}},
   {'directory','/d1/flicky.cct',65,nil,{{after=3,text='dir /dd{ENTER}'},{after=12,text='dir /dd/cmds{ENTER}'}}},
   {'small-read','/d1/flicky.cct',65,nil,{{after=3,text='/dd/cmds/list /dd/startup{ENTER}'},{after=12,text='/dd/cmds/list /dd/startup{ENTER}'}}},
   {'periodic','/d1/flicky.cct',120,nil,{{after=1,text='diskshort /d1/synthetic30.vgm &{ENTER}'}},true},
   {'sustained','/d1/flicky.cct',120,nil,{{after=1,text='diskburst /d1/synthetic30.vgm &{ENTER}'}},true},
   {'playlist','/d1/irq-real.m3u',150,nil,{{after=2,text='echo PLAYLIST{ENTER}'},{after=35,text='/dd/cmds/pwd{ENTER}'}}}
  }
  if p.hardening then cases={
   {'real-aggress','/d1/aggress.vgm',95},
   {'real-penguin','/d1/pengui03.vgm',100},
   {'real-qix','/d1/qix.vgm',115},
   {'real-cct','/d1/penguin.cct',110},
   {'original-cct','/d1/penguin.cct',125,nil,nil,nil,'/d1/cctplay'},
   {'envelope','/d1/envelope.vgm',30},
   {'mixed','/d1/mixed.vgm',40},
   {'saturation','/d1/saturation.vgm',25},
   {'long','/d1/streamlong.vgm',260},
   {'floppy-dir','/d1/flicky.cct',85,nil,{{after=3,text='dir /d1{ENTER}'},{after=12,text='dir /d1{ENTER}'}}},
   {'cctstop','/d1/sparse.vgm',45,nil,nil,nil,nil,'graceful'}
  } end
  local thread=coroutine.create(function()
   for i,c in ipairs(cases) do if i>=(p.first or 1) and i<=(p.last or #cases) then
    case_name=c[1]
    commands.irq_stream_case({name=p.prefix..'-'..c[1],player_crc=p.player_crc,layout=p.layout,fast=p.fast,
      command=(c[7] or p.player or 'cctirq')..' -psg 2 -l 0 '..c[2],duration=c[3],concurrent=c[4],inputs=c[5],reap=c[6],signal=c[8],after=2})
    while active do wait(1) end
    if failure then break end
   end end
   series=false
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end
 commands.irq_stream_lifecycle=function(p)
  assert(not series and not active);series=true
  local cases={
   {'kill','cctirq -psg 2 -l 0 /d1/ark1.cct',45,'kill',1},
   {'burst-stop','cctirq -psg 2 /d1/cancel.vgm',65,'graceful',.2},
   {'playlist-stop','cctirq -psg 2 -l 0 /d1/irq-real.m3u',100,'graceful',5.5},
   {'loop-stop','cctirq -psg 2 -l F /d1/loop.vgm',40,'graceful',.85},
   {'missing-file','cctirq -psg 2 /d1/absent.vgm',15},
   {'wrong-slot','cctirq -psg 1 /d1/ark1.cct',40},
   {'underrun','/d1/streamunder',25},
   {'owner-reject','cctirq -psg 2 -l F /d1/loop.vgm',50,'graceful',10,{{after=2,text='/d1/streamunder &{ENTER}'}}},
   {'restart','cctirq -psg 2 -l 0 /d1/flicky.cct',65},
   {'truncated','cctirq -psg 2 /d1/truncated.vgm',30},
   {'empty','cctirq -psg 2 /d1/empty.vgm',15}
  }
  local thread=coroutine.create(function()
   for i,c in ipairs(cases) do if i>=(p.first or 1) and i<=(p.last or #cases) then
    case_name=c[1]
    commands.irq_stream_case({name=p.prefix..'-'..c[1],player_crc=p.player_crc,layout=p.layout,fast=p.fast,
     command=c[2],duration=c[3],signal=c[4],after=c[5],inputs=c[6],reap=c[6]~=nil})
    while active do wait(1) end
    if failure then break end
   end end
   series=false
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end
 commands.irq_stream_matrix_status=function() return {active=series,current=case_name,failure=failure} end

 commands.irq_stream_status=function() return {active=active,failure=failure} end
end
