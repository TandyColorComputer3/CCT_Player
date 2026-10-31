-- Opt-in fixed comparison series. Requires preloaded irqpack and cctpark,
-- explicit iniz ctclock psgq, verified clock address and queue layout.
return function(commands,array,encode)
 local m=manager.machine;local active=false;local current=nil
 commands.irq_series=function(p)
  assert(not active and not commands.irq_capture_status().active and not commands.reliability_status().active)
  local cases={{'park-idle','cctpark -psg 2 /d1/synthetic30.vgm'},
   {'queue-idle','irqprobe'}, {'park-command','cctpark -psg 2 /d1/synthetic30.vgm',true},
   {'queue-command','irqprobe',true},{'park-command-repeat','cctpark -psg 2 /d1/synthetic30.vgm',true},
   {'queue-command-repeat','irqprobe',true}}
  local function wait(s) assert(emu.wait(s),'discontinuity') end
  local function type(s) assert(m.natkeyboard.empty and not m.natkeyboard.is_posting);commands.type({text=s..'{ENTER}'}) end
  active=true
  local thread=coroutine.create(function()
   for i,c in ipairs(cases) do
    if i>=(p.first or 1) and i<=(p.last or #cases) then
     current=c[1];m.video.throttled=false;type('W');wait(2)
     local prefix='emulator/images/reliability/logs/'..(p.prefix or 'irq-')..c[1]
     local config={};for k,v in pairs(p.layout) do config[k]=v end
     config.duration=45;config.path=prefix..'.json'
     commands.irq_capture(config)
     local inputs=c[3] and {{after=5,text='/dd/cmds/pwd{ENTER}'},{after=15,text='/dd/cmds/mfree{ENTER}'},{after=25,text='echo RESPONSIVE{ENTER}'}} or nil
     commands.reliability_start({duration=45,interval_us=100,path=prefix..'-clock.json',code=p.code,storage=p.storage,input_anchor='psg',inputs=inputs})
     commands.reliability_audio({path=prefix..'.wav'})
     type(c[2]..' &')
     while commands.irq_capture_status().active or commands.reliability_status().active do wait(1) end
     commands.reliability_audio({});m.video.throttled=false
     type('W');wait(2);commands.snapshot({path=(p.prefix or 'irq-')..c[1]..'.png'})
    end
   end
   active=false;current=nil;m.video.throttled=true
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end
 commands.irq_series_status=function() return {active=active,current=current} end
end
