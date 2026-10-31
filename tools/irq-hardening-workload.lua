-- Cold-launch tests: observe hardware, resources and modules without pinning
-- PSGStream in system space. Caller detaches diagnostic packs beforehand.
return function(commands,array,encode)
 local m=manager.machine;local active=false;local failure=nil
 commands.irq_standalone_case=function(p)
  assert(not active and not commands.reliability_status().active)
  assert(p.name:match('^[%w_-]+$'))
  active=true;failure=nil
  local thread=coroutine.create(function()
   local ok,err=xpcall(function()
    local function wait(t) assert(emu.wait(t),'discontinuity') end
    local function type(s)
     local deadline=m.time:as_double()+60
     while not m.natkeyboard.empty or m.natkeyboard.is_posting do assert(m.time:as_double()<deadline);wait(.1) end
     commands.type({text=s..'{ENTER}'})
     while not m.natkeyboard.empty or m.natkeyboard.is_posting do assert(m.time:as_double()<deadline);wait(.1) end
     wait(2)
    end
    local prefix='emulator/images/reliability/logs/'..p.name
    local before={modules=commands.stability_modules({}),resources=commands.irq_resources(),tables=commands.irq_tables({})}
    commands.reliability_start({duration=p.duration,interval_us=100,path=prefix..'-clock.json',input_anchor='psg',inputs=p.inputs})
    commands.reliability_audio({path=prefix..'.wav'});m.video.throttled=not p.fast
    type(p.command..' &')
    while commands.reliability_status().active do wait(.2) end
    commands.reliability_audio({});m.video.throttled=false
    type('W');wait(2)
    local after={modules=commands.stability_modules({}),resources=commands.irq_resources(),tables=commands.irq_tables({})}
    local f=assert(io.open(prefix..'-resources.json','w'));f:write(encode({before=before,after=after}));f:close()
    commands.snapshot({path=p.name..'.png'})
   end,debug.traceback)
   if not ok then failure=tostring(err) end
   active=false;m.video.throttled=true
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end
 local series=false;local current=nil
 commands.irq_standalone_series=function(p)
  assert(not active and not series);series=true
  local cases={
   {'missing','/d1/cctirq /d1/absent.vgm',18},
   {'empty','/d1/cctirq /d1/empty.vgm',18},
   {'dual','/d1/cctirq /d1/dual.vgm',22},
   {'init','/d1/failinit /d1/arkanoid.vgm',22},
   {'virq','/d1/failvirq /d1/arkanoid.vgm',22},
   {'allocation','/d1/failalloc /d1/flicky.cct',30},
   {'cct','/d1/cctirq -l 0 /d1/flicky.cct',65},
   {'playlist','/d1/cctirq -l 0 /d1/list.m3u',110},
   {'repeat1','/d1/cctirq -l 0 /d1/arkanoid.vgm',35},
   {'repeat2','/d1/cctirq -l 0 /d1/arkanoid.vgm',35}
  }
  if p.stops then cases={
   {'dense-stop','irqsuper 150 /d1/cancel.vgm',45},
   {'empty-stop','irqsuper 360 /d1/sparse.vgm',40},
   {'transition-stop','irqsuper 600 /d1/list.m3u',50},
   {'kill-queued','irqkill 1500 /d1/flicky.cct',65},
   {'kill-loading','irqkill 240 /d1/flicky.cct',40},
   {'stop-repeat1','irqsuper 360 /d1/sparse.vgm',40},
   {'stop-repeat2','irqsuper 360 /d1/sparse.vgm',40}
  } end
  local thread=coroutine.create(function()
   for i,c in ipairs(cases) do if i>=(p.first or 1) and i<=(p.last or #cases) then
    current=c[1];commands.irq_standalone_case({name=p.prefix..'-'..c[1],command=c[2],duration=c[3],fast=p.fast})
    while active do assert(emu.wait(1)) end
    if failure then break end
   end end
   series=false
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end
 commands.irq_standalone_status=function() return {active=active,series=series,current=current,failure=failure} end
end
