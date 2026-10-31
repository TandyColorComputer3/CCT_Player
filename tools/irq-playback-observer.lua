-- Read-only MAME instrumentation for the opt-in PSGQueue module.
-- Version-specific offsets supplied from the assembler listing, CRC checked.
return function(commands,array,encode)
 local m=manager.machine;local cpu=m.devices[':maincpu'];local mem=cpu.spaces.program
 local function item(d,n) return emu.item(assert(d.items['0/'..n])) end
 local mmu=item(m.devices[':gime'],'m_mmu');local regs=item(m.devices[':gime'],'m_gime_registers');local ram=item(m.devices[':ram'],'m_pointer')
 local function sb(a) return ram:read(mmu:read(a//8192)*8192+a%8192) end
 local function sw(a) return sb(a)*256+sb(a+1) end
 local active=false
 local function tables()
  local virqs={};local tablebase=sw(0xb0)
  for a=tablebase,tablebase+62,2 do local q=sw(a);if q==0 then break end;virqs[#virqs+1]={address=q,count=sw(q),reset=sw(q+2),status=sb(q+4)} end
  local polls={};local p=sw(0x82)
  local n=sb(sw(0x24)+12);assert(n<=64);for i=0,n-1 do local a=p+i*11;if sw(a)~=0 then polls[#polls+1]={address=sw(a),handler=sw(a+4),storage=sw(a+6),mask=sb(a+3)} end end
  return {virqs=array(virqs),polls=array(polls)}
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
  assert(not active);assert(p.duration>0 and p.duration<=180)
  assert(p.path:match('^emulator/images/reliability/logs/[%w_-]+%.json$'))
  local initial=inspect(p);local base=initial.base;local events={};local taps={};local drops=0;local start=m.time:as_double();local inside=nil
  local function emit(kind,e) e=e or {};e.kind=kind;e.seconds=m.time:as_double();if #events<100000 then events[#events+1]=e else drops=drops+1 end end
  local function state(u) return {u=u,ticks=sw(u+p.ticks),state=sb(u+p.state),count=sw(u+p.count),budgets=sw(u+p.budgets),underruns=sw(u+p.unders),owner=sw(u+p.owner)} end
  local function hook(off,fn)
   local a=base+off
   taps[#taps+1]=mem:install_read_tap(a,a,'irq-probe-'..off,function(addr,d)
    if regs:read(1)&1==0 and cpu.state.PC.value==addr+1 then fn() end
   end)
  end
  hook(p.irq,function() inside=cpu.state.U.value;local e=state(inside);e.current=sb(sw(0x50));e.cc=cpu.state.CC.value;emit('handler-enter',e) end)
  hook(p.ok,function() if inside then emit('handler-exit',state(inside));inside=nil end end)
  taps[#taps+1]=mem:install_write_tap(0xff5e,0xff5f,'irq-probe-psg',function(a,d) emit('psg-write',{address=a,data=d,in_handler=inside~=nil,task=regs:read(1)&1}) end)
  taps[#taps+1]=mem:install_write_tap(0xff7f,0xff7f,'irq-probe-mpi',function(a,d) emit('mpi-write',{data=d,in_handler=inside~=nil}) end)
  active=true
  local thread=coroutine.create(function()
   if not emu.wait(p.duration) then emit('discontinuity') end
   for _,t in ipairs(taps) do t:remove() end
   local f=assert(io.open(p.path,'w'));f:write(encode({start=start,finish=m.time:as_double(),initial=initial,final=inspect(p),config=p,events=array(events),droppedEvents=drops}));f:close()
   active=false;m.video.throttled=true
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true,base=base}
 end
 commands.irq_capture_status=function() return {active=active} end
 dofile("tools/irq-workloads.lua")(commands,array,encode)
end
