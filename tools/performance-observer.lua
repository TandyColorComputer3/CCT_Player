-- Host-only MAME 0.289 observer for an exclusively owned test guest.
-- Load from a local bridge: dofile(path)(commands, mark_array, json_encode).
-- No guest writes or extra reads of hardware registers. Read taps return nil.
-- Caller supplies verified system-map CCTClock code/storage addresses; restart
-- observation after unload/reload. Logs are bounded and overflow invalidates a run.
return function(commands, array, encode)
  local m = manager.machine
  local cpu = m.devices[':maincpu']
  local mem = cpu.spaces.program
  local mmu = emu.item(m.devices[':gime'].items['0/m_mmu'])
  local gr = emu.item(m.devices[':gime'].items['0/m_gime_registers'])
  local ram = emu.item(m.devices[':ram'].items['0/m_pointer'])
  local function sys(a) return ram:read(mmu:read(math.floor(a / 8192)) * 8192 + a % 8192) end
  local function reg(n) return cpu.state[n].value end
  local active, taps, events, dropped, frames = false, {}, {}, 0, 0
  local config, resets = nil, 0
  local function event(kind, a, d)
    if not active then return end
    if #events >= 500000 then dropped = dropped + 1; return end
    events[#events+1] = {kind=kind, seconds=m.time:as_double(), address=a,
      data=d, pc=reg('PC'), u=reg('U'), cc=reg('CC'), task=gr:read(1)&1}
  end
  -- Frames are independent video cadence observations, NOT IRQ assertions or
  -- CPU-utilization samples. A pending GIME bit can coalesce several edges.
  local frame_subscription = emu.add_machine_frame_notifier(function()
    if active then frames=frames+1; event('frame') end
  end)
  local reset_subscription = emu.add_machine_reset_notifier(function()
    if active then resets=resets+1; event('reset') end
  end)
  commands.performance_start = function(p)
    assert(not active, 'already recording')
    local code, data = assert(p.code), assert(p.storage)
    assert(code >= 0 and code + 184 < 0xff00 and data >= 0 and data + 38 < 0xff00)
    -- Exact baseline driver identity, including CRC, before using its offsets.
    assert(sys(code)==0x87 and sys(code+1)==0xcd and sys(code+2)==0 and sys(code+3)==184)
    assert(sys(code+181)==0x8f and sys(code+182)==0x5e and sys(code+183)==0xed,
      'CCTClock baseline identity mismatch')
    local table = sys(0xb0)*256+sys(0xb1)
    local registered = false
    for i=0,31 do
      local packet=sys(table+2*i)*256+sys(table+2*i+1)
      if packet==0 then break end
      if packet==data+29 then registered=true end
    end
    assert(registered and sys(data+31)==0 and sys(data+32)==1,
      'storage is not a live one-tick VIRQ packet')
    config={code=code,storage=data}; events={}; dropped=0; frames=0; resets=0; active=true
    local function read(lo, hi, kind, filter)
      taps[#taps+1]=mem:install_read_tap(lo,hi,'cct-perf-'..kind,function(a,d)
        if not filter or filter() then event(kind,a,d) end
      end)
    end
    local function write(lo, hi, kind, filter)
      taps[#taps+1]=mem:install_write_tap(lo,hi,'cct-perf-'..kind,function(a,d)
        if not filter or filter() then event(kind,a,d) end
      end)
    end
    local function driver() return (gr:read(1)&1)==0 and reg('U')==data and reg('PC')>=code and reg('PC')<code+184 end
    read(0xff92,0xff92,'irq-ack')
    read(data+34,data+37,'clock-read',driver)
    write(data+34,data+37,'clock-write',driver)
    write(0x2e,0x2e,'os-tick',function() return (gr:read(1)&1)==0 end)
    write(0xff48,0xff48,'fdc-command')
    write(0xff5e,0xff5f,'psg-write')
    write(0xff7f,0xff7f,'mpi-write')
    event('start')
    return config
  end
  commands.performance_finish = function(p)
    assert(active, 'not recording'); event('finish'); active=false
    for _,tap in ipairs(taps) do tap:remove() end; taps={}
    local out={config=config,events=array(events),frames=frames,droppedEvents=dropped,resetCount=resets}
    local f=assert(io.open(assert(p.path),'w')); f:write(encode(out)); f:close()
    return {events=#events,frames=frames,droppedEvents=dropped,path=p.path}
  end
  -- Keep subscription alive for the bridge lifetime.
  commands.performance_observer_status=function() return {active=active,events=#events,droppedEvents=dropped,subscribed=frame_subscription~=nil and reset_subscription~=nil} end
end
