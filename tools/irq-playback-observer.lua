-- Read-only MAME instrumentation for the opt-in PSGQueue module.
-- Version-specific offsets supplied from the assembler listing, CRC checked.
return function(commands,array,encode)
 local m=manager.machine;local cpu=m.devices[':maincpu'];local mem=cpu.spaces.program
 local function item(d,n) return emu.item(assert(d.items['0/'..n])) end
 local mmu=item(m.devices[':gime'],'m_mmu');local regs=item(m.devices[':gime'],'m_gime_registers');local ram=item(m.devices[':ram'],'m_pointer')
 local function sb(a) return ram:read(mmu:read(a//8192)*8192+a%8192) end
 local function sw(a) return sb(a)*256+sb(a+1) end
 local active=false;local first_write=nil;local producer=nil;local live_owner=nil;local first_allocation=nil
 local function tables()
  local virqs={};local tablebase=sw(0xb0)
  for a=tablebase,tablebase+62,2 do local q=sw(a);if q==0 then break end;virqs[#virqs+1]={address=q,count=sw(q),reset=sw(q+2),status=sb(q+4)} end
  local polls={};local p=sw(0x82)
  local n=sb(sw(0x24)+12);assert(n<=64);for i=0,n-1 do local a=p+i*11;if sw(a)~=0 then polls[#polls+1]={address=sw(a),handler=sw(a+4),storage=sw(a+6),mask=sb(a+3)} end end
  return {virqs=array(virqs),polls=array(polls)}
 end
 commands.irq_resources=function()
  local lo,hi=sw(0x40),sw(0x42);assert(hi>=lo and hi-lo<=512)
  local blocks={};for a=lo,hi-1 do blocks[#blocks+1]=sb(a) end
  local pages={};local b=sw(0x4e);for a=b,b+31 do pages[#pages+1]=sb(a) end
  local procs={};local t=sw(0x48)
  for id=1,64 do local p=sb(t+id)*256;if p~=0 and sb(p)==id then
   local paths={};for a=p+48,p+63 do paths[#paths+1]=sb(a) end
   procs[#procs+1]={id=id,module=sw(p+17),paths=array(paths)}
  end end
  return {blocks=array(blocks),system_pages=array(pages),processes=array(procs)}
 end
 commands.irq_process_info=function(p)
  assert(p.pid>=1 and p.pid<=255)
  local proc=sb(sw(0x48)+p.pid)*256
  if proc==0 or sb(proc)~=p.pid then return {live=false} end
  local ptr=sw(proc+17)
  local function pb(a) local bank=sw(proc+64+2*(a//8192));assert(bank<256);return ram:read(bank*8192+a%8192) end
  if pb(ptr)~=0x87 or pb(ptr+1)~=0xcd then return {live=false} end
  local size=pb(ptr+2)*256+pb(ptr+3);local off=pb(ptr+4)*256+pb(ptr+5);local name=''
  for i=0,28 do local b=pb(ptr+off+i);name=name..string.char(b&127);if b&128~=0 then break end end
  local crc=string.format('%02X%02X%02X',pb(ptr+size-3),pb(ptr+size-2),pb(ptr+size-1))
  return {live=true,pid=p.pid,name=name,crc=crc,state=sb(proc+12)}
 end
 commands.irq_tables=function(p) local t=tables();if p.path then assert(p.path:match("^emulator/images/reliability/logs/[%w_-]+%.json$"));local f=assert(io.open(p.path,"w"));f:write(encode(t));f:close() end;return t end
 local function inspect(p)
  local base=nil
  for a=0,0xfe00-p.size do
   if sb(a)==0x87 and sb(a+1)==0xcd and sw(a+2)==p.size and sb(a+p.size-3)==p.crc[1] and sb(a+p.size-2)==p.crc[2] and sb(a+p.size-1)==p.crc[3] then base=a;break end
  end
  assert(base,'driver not mapped in system space')
  local t=tables();t.base=base
  t.system_mmu=array({mmu:read(0),mmu:read(1),mmu:read(2),mmu:read(3),mmu:read(4),mmu:read(5),mmu:read(6),mmu:read(7)})
  return t
 end
 commands.irq_inspect=inspect
 commands.irq_capture=function(p)
  assert(not active);assert(p.duration>0 and p.duration<=300)
  assert(p.path:match('^emulator/images/reliability/logs/[%w_-]+%.json$'))
  local initial=inspect(p);local base=initial.base;local events={};local taps={};local drops=0;local start=m.time:as_double();local inside=nil;local append=nil
  local function emit(kind,e) e=e or {};e.kind=kind;e.seconds=m.time:as_double();if #events<250000 then events[#events+1]=e else drops=drops+1 end end
  local function state(u) return {u=u,ticks=sw(u+p.ticks),state=sb(u+p.state),count=sw(u+p.count),head=sb(u+p.count+2),tail=sb(u+p.count+3),budgets=sw(u+p.budgets),underruns=sw(u+p.unders),owner=sw(u+p.owner)} end
  -- A host status query may land inside a transient kernel MMU mapping.
  -- Treat unavailable tables as an unknown sample, never a freed queue.
  -- Initial/final inspections still require validated tables.
  live_owner=function()
   local ok,t=pcall(tables);if not ok then return nil end
   for _,e in ipairs(t.polls) do if e.handler==base+p.irq then return state(e.storage) end end
   return nil
  end
  local function hook(off,fn)
   local a=base+off
   taps[#taps+1]=mem:install_read_tap(a,a,'irq-probe-'..off,function(addr,d)
    if regs:read(1)&1==0 and cpu.state.PC.value==addr+1 then fn() end
   end)
  end
  hook(p.irq,function() inside=cpu.state.U.value;local e=state(inside);e.current=sb(sw(0x50));e.cc=cpu.state.CC.value;emit('handler-enter',e) end)
  hook(p.ok,function()
   if inside then emit('handler-exit',state(inside));inside=nil;return end
   if append then local e=state(append);e.cc=cpu.state.CC.value;emit('append-ok',e);append=nil end
  end)
  if p.append then
   hook(p.append,function() append=cpu.state.U.value;local e=state(append);e.cc=cpu.state.CC.value;e.current=sb(sw(0x50));producer=e.current;emit('append-enter',e) end)
   for _,off in ipairs({p.busy,p.invalid}) do hook(off,function() if append then local e=state(append);e.cc=cpu.state.CC.value;emit('append-reject',e);append=nil end end) end
  end
  if p.setstat then hook(p.setstat,function() local code=cpu.state.A.value;if code==0x84 and not first_allocation then first_allocation=m.time:as_double();producer=sb(sw(0x50)) end;emit('setstat',{code=code}) end) end
  if p.getstat then hook(p.getstat,function() emit('getstat',{code=cpu.state.A.value}) end) end
  if p.locked then
   hook(p.locked,function() emit('append-locked') end)
   for _,off in ipairs({p.unlock,p.unlockbusy,p.unlockinvalid}) do hook(off,function() emit('append-unlock') end) end
  end
  taps[#taps+1]=mem:install_read_tap(0xff5d,0xff5d,'irq-control-read',function(a,d) emit('control-read',{data=d}) end)
  taps[#taps+1]=mem:install_write_tap(0xff5d,0xff5d,'irq-control-write',function(a,d) emit('control-write',{data=d}) end)
  taps[#taps+1]=mem:install_write_tap(0xff5e,0xff5f,'irq-probe-psg',function(a,d) if inside and a==0xff5f and not first_write then first_write=m.time:as_double() end;emit('psg-write',{address=a,data=d,in_handler=inside~=nil,task=regs:read(1)&1}) end)
  taps[#taps+1]=mem:install_write_tap(0xff7f,0xff7f,'irq-probe-mpi',function(a,d) emit('mpi-write',{data=d,in_handler=inside~=nil}) end)
  active=true;first_write=nil;producer=nil;first_allocation=nil
  local thread=coroutine.create(function()
   if not emu.wait(p.duration) then emit('discontinuity') end
   for _,t in ipairs(taps) do t:remove() end
   local f=assert(io.open(p.path,'w'));f:write(encode({start=start,finish=m.time:as_double(),initial=initial,final=inspect(p),config=p,events=array(events),droppedEvents=drops}));f:close()
   active=false;m.video.throttled=true
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true,base=base}
 end
 commands.irq_capture_status=function() return {active=active,first_write=first_write,first_allocation=first_allocation,producer=producer,queue=live_owner and live_owner() or nil} end
 dofile("tools/irq-workloads.lua")(commands,array,encode)
 dofile("tools/irq-density-workload.lua")(commands,array,encode)
 dofile("tools/irq-stream-workload.lua")(commands,array,encode)
 dofile("tools/irq-hardening-workload.lua")(commands,array,encode)
end
