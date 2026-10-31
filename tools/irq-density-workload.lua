-- Bounded diagnostic case, with no guest memory writes from instrumentation.
-- Requires the previous pack already detached; each case leaves a loaded pack.
return function(commands,array,encode)
 local m=manager.machine;local active=false;local failure=nil
 commands.irq_density_case=function(p)
  assert(not active and not commands.irq_capture_status().active and not commands.reliability_status().active)
  assert(p.name:match('^[%w_-]+$') and p.pack:match('^[%w]+$'))
  assert(p.duration>=12 and p.duration<=300)
  active=true;failure=nil
  local function wait(t) assert(emu.wait(t),'discontinuity') end
  local function drain()
   local deadline=m.time:as_double()+60
   while not m.natkeyboard.empty or m.natkeyboard.is_posting do assert(m.time:as_double()<deadline,'keyboard did not drain');wait(.1) end
  end
  local function type(s) drain();commands.type({text=s..'{ENTER}'});drain();wait(1) end
  local thread=coroutine.create(function()
   local ok,err=xpcall(function()
   m.video.throttled=false
   type('unlink CCTClock');wait(2)
   type('load /d1/'..p.pack);wait(15)
   type('iniz ctclock psgq');wait(3)
   local info=commands.irq_inspect(p.layout);local code=info.base-225;local storage=nil
   for _,entry in ipairs(info.polls) do if entry.handler==code+156 then storage=entry.storage end end
   assert(storage,'clock registration missing')
   if p.counter then type((p.duration>=220 and 'countlong' or 'timeload')..' &');wait(2) end
   local prefix='emulator/images/reliability/logs/'..p.name
   local cfg={};for k,v in pairs(p.layout) do cfg[k]=v end
   cfg.duration=p.duration;cfg.path=prefix..'.json';commands.irq_capture(cfg)
   commands.reliability_start({duration=p.duration,interval_us=100,path=prefix..'-clock.json',code=code,storage=storage,input_anchor='psg',inputs=p.inputs})
   commands.reliability_audio({path=prefix..'.wav'})
   m.video.throttled=not p.fast
   type('irqdense &')
   while commands.irq_capture_status().active or commands.reliability_status().active do wait(1) end
   commands.reliability_audio({});m.video.throttled=false
   type('W');wait(2)
   if p.counter then type('W');wait(2) end
   commands.snapshot({path=p.name..'.png'})
   type('deiniz psgq ctclock');wait(3)
   commands.irq_tables({path=prefix..'-tables.json'})
   end,debug.traceback)
   if not ok then failure=tostring(err) end
   active=false;m.video.throttled=true
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end
 commands.irq_density_status=function() return {active=active,failure=failure} end
end
