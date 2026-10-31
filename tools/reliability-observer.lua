-- Host-only bounded sampler for MAME 0.289, HD6309 EOU test guests.
-- Read-only saved device state; never read interrupt-acknowledge registers.
-- Timer sampling is not an instruction trace: retain resolution and gaps.
-- Use only in an exclusively owned guest. Do not reload this addon while active.
-- IRQ source/driver addresses are version-specific; see CLOCK-RELIABILITY.md.
-- Load via a private bridge: dofile(path)(commands, mark_array, json_encode).
return function(commands, array, encode)
  local m=manager.machine
  local cpu=m.devices[':maincpu']; local g=m.devices[':gime']
  local function item(d,n) local index=assert(d.items['0/'..n],n);return emu.item(index) end
  local cc=item(cpu,'m_cc'); local pc=item(cpu,'m_pc.w')
  local halt=item(cpu,'m_input.m_curstate'); local susp=item(cpu,'m_nextsuspend')
  local zone=item(g,'m_logical_scanline_zone'); local line=item(g,'m_physical_scanline')
  local irq=item(g,'m_irq'); local regs=item(g,'m_gime_registers')
  local mmu=item(g,'m_mmu'); local ram=item(m.devices[':ram'],'m_pointer')
  local function sys(a) return ram:read(mmu:read(a//8192)*8192+a%8192) end
  -- Kernel mapping transitions can temporarily hide process descriptors.
  -- Validate against D.PrcDBT; 0 means unknown, never a guessed PID.
  local function owner()
    local p=sys(0x50)*256+sys(0x51)
    if p<0x100 or p>=0xfe00 or p%256~=0 then return 0 end
    local pid=sys(p);local tbl=sys(0x48)*256+sys(0x49)
    if pid==0 or tbl<0x100 or tbl+pid>=0xfe00 or sys(tbl+pid)*256~=p then return 0 end
    return pid
  end
  local active=false; local serial=0
  local resets=0
  local reset_subscription=emu.add_machine_reset_notifier(function() resets=resets+1 end)
  commands.reliability_load_scheduling=function()
    assert(not commands.scheduling_status or not commands.scheduling_status().active,'call observer active')
    assert(not commands.scheduling_series_status or not commands.scheduling_series_status().active,'workload series active')
    dofile('tools/scheduling-observer.lua')(commands,array,encode)
    dofile('tools/scheduling-workloads.lua')(commands,array,encode)
    return {loaded=true}
  end
  commands.reliability_speed=function(p) m.video.throttled=not p.fast;return {throttled=m.video.throttled} end
  commands.reliability_audio=function(p)
    if p.path then
      assert(p.path:match('^emulator/images/reliability/logs/[%w_-]+%.wav$'))
      return {started=m.sound:start_recording(p.path)}
    end
    m.sound:stop_recording();return {stopped=true}
  end
  commands.reliability_start=function(p)
    assert(not active,'already sampling')
    local us=assert(tonumber(p.interval_us)); local duration=assert(tonumber(p.duration))
    assert(us>=1 and us<=1000 and duration>0 and duration<=360)
    local path=assert(p.path); assert(path:match('^emulator/images/reliability/logs/[%w_-]+%.json$'))
    if p.storage then
      local code,storage=assert(p.code),p.storage
      assert(sys(code)==0x87 and sys(code+1)==0xcd and sys(code+2)==0 and sys(code+3)==184)
      assert(sys(code+181)==0x8f and sys(code+182)==0x5e and sys(code+183)==0xed,'driver identity')
      local tbl=sys(0xb0)*256+sys(0xb1);local found=false
      for i=0,31 do
        local packet=sys(tbl+2*i)*256+sys(tbl+2*i+1)
        if packet==0 then break end
        if packet==storage+29 then found=true end
      end
      assert(found and sys(storage+31)==0 and sys(storage+32)==1,'live one-tick packet')
    end
    serial=serial+1; local token=serial;local initial_resets=resets; active=true
    local events, taps, bins={}, {}, {}; local dropped=0; local samples=0; local maxgap=0
    local begin=m.time:as_double(); local last=begin; local previous=nil; local previous_zone=nil; local previous_owner=nil
    local input_index=1;local input_epoch=nil;local selected_register=nil;local input_track=0
    local function emit(kind,fields)
      if #events>=1500000 then dropped=dropped+1;return end
      local e=fields or {};e.kind=kind;e.seconds=m.time:as_double();events[#events+1]=e
    end
    local mem=cpu.spaces.program
    taps[#taps+1]=mem:install_write_tap(0xff7f,0xff7f,'reliability-mpi',function(a,d)
      emit('mpi-write',{data=d})
    end)
    taps[#taps+1]=mem:install_read_tap(0xff92,0xff92,'reliability-ack',function(a,d)
      emit('irq-ack',{data=d,pc=pc:read(0),cc=cc:read(0)})
    end)
    taps[#taps+1]=mem:install_write_tap(0xff5e,0xff5f,'reliability-psg',function(a,d)
      emit('psg-write',{address=a,data=d,pid=owner()})
      if a==0xff5e then selected_register=d
      elseif p.input_anchor=='psg' then
        if selected_register==7 and d==63 then
          if p.repeat_inputs then input_epoch=nil;input_index=1 end
        elseif not input_epoch then
          input_epoch=m.time:as_double();input_track=input_track+1
        end
      end
    end)
    taps[#taps+1]=mem:install_write_tap(0xff48,0xff48,'reliability-fdc',function(a,d)
      emit('fdc-command',{data=d,cc=cc:read(0)})
    end)
    if p.storage then
      local storage=tonumber(p.storage)
      taps[#taps+1]=mem:install_read_tap(storage+34,storage+34,'reliability-getstat',function(a,d)
        if (regs:read(1)&1)==0 and cpu.state.U.value==storage and pc:read(0)==p.code+145 then
          emit('clock-call',{pid=owner()})
        end
      end)
      taps[#taps+1]=mem:install_write_tap(storage+37,storage+37,'reliability-clock',function(a,d)
        if (regs:read(1)&1)==0 and cpu.state.U.value==storage and pc:read(0)==p.code+164 then
          emit('clock-tick',{data=d,pid=owner()})
        end
      end)
    end
    local thread=coroutine.create(function()
      while active and serial==token do
        if resets~=initial_resets then emit('discontinuity',{reason='machine reset'});break end
        local now=m.time:as_double();local dt=now-last;maxgap=math.max(maxgap,dt);last=now
        local input=p.inputs and p.inputs[input_index]
        local anchor=p.input_anchor=='psg' and input_epoch or begin
        if p.input_anchor=='psg' and not input_epoch then anchor=nil end
        if input and anchor and now-anchor>=input.after then
          local keyboard=m.natkeyboard
          if not keyboard.empty or keyboard.is_posting then emit('discontinuity',{reason='keyboard queue overlap'});break end
          keyboard.in_use=true;keyboard:post_coded(input.text)
          emit('host-input',{text=input.text,track=input_track});input_index=input_index+1
        end
        local c=cc:read(0)&0x50;local h=halt:read(66);local s=susp:read(0)
        local pid=owner();local task=regs:read(1)&1;local z=zone:read(0)
        local key=string.format('%d:%d:%d:%d',h,c,pid,task)
        bins[key]=(bins[key] or 0)+1;samples=samples+1
        local ownership=pid*2+task
        if ownership~=previous_owner then emit('schedule',{pid=pid,task=task});previous_owner=ownership end
        local state=h*256+c
        if state~=previous then emit('cpu-state',{halt=h,mask=c,pc=pc:read(0),suspend=s,pid=pid,task=task});previous=state end
        if z~=previous_zone then
          emit('video-zone',{zone=z,previous_zone=previous_zone,line=line:read(0),pending=irq:read(0),enable=regs:read(2),global=regs:read(0),halt=h,mask=c,pid=pid,task=task})
          previous_zone=z
        end
        if now-begin>=duration then break end
        if not emu.wait(us/1000000) then emit('discontinuity');break end
      end
      for _,tap in ipairs(taps) do tap:remove() end
      active=false
      m.video.throttled=true
      local result={interval_us=us,start=begin,finish=m.time:as_double(),samples=samples,max_sample_gap=maxgap,
        droppedEvents=dropped,events=array(events),sample_bins=bins,code=p.code,storage=p.storage,
        clock_calls_observed=p.storage~=nil,inputs=p.inputs,resetCount=resets-initial_resets}
      local f=assert(io.open(path,'w'));f:write(encode(result));f:close()
    end)
    local ok,err=coroutine.resume(thread);assert(ok,err)
    return {started=true,path=path,interval_us=us,duration=duration}
  end
  commands.reliability_status=function() return {active=active,seconds=m.time:as_double(),subscribed=reset_subscription~=nil} end
end
