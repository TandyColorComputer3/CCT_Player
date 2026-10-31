-- Bounded, opt-in host workload series for the private scheduling test guest.
-- Requires preloaded cctnice/timeload/diskstress, perfpack, cctpark and ctclock.
-- Uses only normal Shell commands and existing host observers. No guest pokes.
return function(commands,array,encode)
 local m=manager.machine;local active=false;local current=nil;local results={}
 local cases={
  {name='music-idle'},
  {name='music-counter',reader='timeload'},
  {name='music-dir',input='dir /dd'},
  {name='music-command',input='/dd/cmds/pwd'},
  {name='music-smallread',input='/dd/cmds/list /dd/startup'},
  {name='music-periodic-full',command='musicdisk',duration=180},
  {name='music-sustained-complete',command='musicbusy',duration=360},
  {name='music-resident',prepare='load /dd/cmds/pwd',input='pwd'},
 }
 local function type(text) assert(m.natkeyboard.empty and not m.natkeyboard.is_posting);commands.type({text=text..'{ENTER}'}) end
 local function wait(seconds) assert(emu.wait(seconds),'emulation discontinuity') end
 local function jobs()
  local names={cctpark=true,cctnice=true,diskload=true,diskstress=true,timeload=true,musicdisk=true,musicbusy=true}
  for pid=1,32 do
   local p=commands.stability_state({pid=pid}).target
   if p and names[p.name] and p.status&1==0 then return true end
  end
  return false
 end
 commands.scheduling_series=function(p)
  assert(not active);assert(not commands.scheduling_status().active and not commands.reliability_status().active)
  active=true;results={}
  local thread=coroutine.create(function()
   for index,case in ipairs(cases) do
    if index>=(p.first or 1) and index<=(p.last or #cases) then
     current=case.name;m.video.throttled=false
     assert(not jobs(),'previous workload still alive')
     type('W');wait(2)
     if case.prepare then type(case.prepare);wait(5) end
     local duration=case.duration or 120
     local inputs=case.input and {{after=.2,text=case.input..'{ENTER}'}} or nil
     local path='emulator/images/reliability/logs/'..case.name
     commands.reliability_audio({path=path..'.wav'})
     commands.scheduling_start({base=49152,target_offset=709,interval_us=1000,duration=duration,path=path..'-calls.json',calls={{offset=7692,label='GetStat'},{offset=7739,label='Sleep'},{offset=7565,label='Budget'},{offset=7480,label='Epoch'}}})
     commands.reliability_start({interval_us=100,duration=duration,path=path..'.json',code=8192,storage=22272,inputs=inputs,input_anchor='psg',repeat_inputs=true})
     if case.reader then type(case.reader..' &');wait(3) end
     type(case.command and (case.command..' &') or 'cctnice 128 -psg 2 /d1/latency.m3u &')
     while commands.scheduling_status().active or commands.reliability_status().active do wait(1) end
     commands.reliability_audio({});m.video.throttled=false
     local deadline=m.time:as_double()+600
     while jobs() do assert(m.time:as_double()<deadline,'workload did not finish');wait(5) end
     type('W');wait(2)
     commands.snapshot({path=case.name..'.png'})
     results[#results+1]={name=case.name,finished=m.time:as_double()}
     local f=assert(io.open('emulator/images/reliability/logs/music-series.json','w'));f:write(encode({runs=array(results)}));f:close()
    end
   end
   active=false;current=nil;m.video.throttled=true
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end
 commands.scheduling_series_status=function() return {active=active,current=current,finished=array(results)} end
end
