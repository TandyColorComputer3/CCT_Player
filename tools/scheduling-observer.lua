-- Host-only call-boundary and process-queue diagnostic. No guest writes.
-- Version-specific player offsets supplied from its verified assembler listing.
return function(commands,array,encode)
 local m=manager.machine;local cpu=m.devices[':maincpu'];local mem=cpu.spaces.program
 local function item(d,n) local i=assert(d.items['0/'..n]);return emu.item(i) end
 local gr=item(m.devices[':gime'],'m_gime_registers');local mmu=item(m.devices[':gime'],'m_mmu')
 local ram=item(m.devices[':ram'],'m_pointer');local active=false
 local function sb(a) return ram:read(mmu:read(a//8192)*8192+a%8192) end
 local function sw(a) return sb(a)*256+sb(a+1) end
 local function proc(pid) local t=sw(0x48);local p=sb(t+pid)*256;return p>0 and sb(p)==pid and p or nil end
 local function owner() local p=sw(0x50);local id=sb(p);return id>0 and proc(id)==p and id or 0 end
 local function queue(head,p)
  local seen={};local q=sw(head)
  for i=1,64 do if q==0 or seen[q] then return false end;if q==p then return true end;seen[q]=true;q=sw(q+13) end
  return false
 end
 commands.scheduling_start=function(p)
  assert(not active)
  assert(p.duration>0 and p.duration<=360 and p.interval_us>=100 and p.interval_us<=10000)
  assert(p.path:match('^emulator/images/reliability/logs/[%w_-]+%.json$'))
  assert(p.base==49152 and p.target_offset==709,'requires verified cctpark layout')
  for _,call in ipairs(p.calls) do assert(call.offset>=0 and call.offset<=9654 and call.label:match('^[%w_]+$')) end
  active=true
  local ranges={}
  local modules=commands.stability_modules({}).entries
  for _,mod in ipairs(modules) do
   local offset=0
   while offset<mod.size do
    local logical=mod.module+offset;local count=math.min(mod.size-offset,8192-logical%8192)
    local physical=(sw(mod.dat+2*(logical//8192))&255)*8192+logical%8192
    ranges[#ranges+1]={first=physical,last=physical+count-1,name=mod.name,offset=offset}
    offset=offset+count
   end
  end
  local function module_at(pc,task)
   local phys=mmu:read(task*8+pc//8192)*8192+pc%8192
   for _,r in ipairs(ranges) do if phys>=r.first and phys<=r.last then return r.name, r.offset+phys-r.first end end
   return 'unknown',0
  end
  local events,taps={},{};local dropped=0;local start=m.time:as_double();local pid=p.pid;local data_u=nil;local last=nil
  local function emit(kind,fields)
   if #events>=500000 then dropped=dropped+1;return end
   local e=fields or {};e.kind=kind;e.seconds=m.time:as_double();events[#events+1]=e
  end
  local function hook(addr,kind,label)
   taps[#taps+1]=mem:install_read_tap(addr,addr,'latency-'..label..kind,function(a,d)
    local task=gr:read(1)&1;local pc=cpu.state.PC.value
    if task==1 and pc==addr+1 then
     local function ub(a) return ram:read(mmu:read(8+a//8192)*8192+a%8192) end
     -- Reject another process's code at the same logical address.
     if ub(p.base)~=0x87 or ub(p.base+1)~=0xcd or ub(p.base+2)*256+ub(p.base+3)~=9658 then return end
     if ub(p.base+9655)~=0x82 or ub(p.base+9656)~=0x71 or ub(p.base+9657)~=0x91 then return end
     if not pid then pid=owner() end
     emit(kind,{label=label,pid=owner(),pc=pc,u=cpu.state.U.value,x=cpu.state.X.value,y=cpu.state.Y.value,a=cpu.state.A.value,b=cpu.state.B.value,cc=cpu.state.CC.value})
    end
   end)
  end
  for _,call in ipairs(p.calls) do hook(p.base+call.offset,'call-enter',call.label);hook(p.base+call.offset+3,'call-return',call.label) end
  taps[#taps+1]=mem:install_write_tap(0xff5e,0xff5f,'latency-psg',function(a,d)
   if not pid then pid=owner() end
   if owner()==pid then data_u=cpu.state.U.value end
   emit('psg-write',{address=a,data=d,pid=owner(),u=cpu.state.U.value})
  end)
  local returns={};local pending={}
  taps[#taps+1]=mem:install_read_tap(0xfff4,0xfff4,'latency-swi2',function(a,d)
   if (gr:read(1)&1)~=1 then return end
   local pc=cpu.state.PC.value;local current=owner()
   local function ub(a) return ram:read(mmu:read(8+a//8192)*8192+a%8192) end
   local service=ub(pc);local ret=(pc+1)&65535
   emit('os-enter',{pid=current,service=service,pc=pc,a=cpu.state.A.value,b=cpu.state.B.value,x=cpu.state.X.value,y=cpu.state.Y.value,u=cpu.state.U.value})
   pending[current]={service=service,ret=ret}
   if not returns[ret] then
    returns[ret]=true
    taps[#taps+1]=mem:install_read_tap(ret,ret,'latency-os-return',function(addr,value)
     local id=owner();local call=pending[id]
     if (gr:read(1)&1)==1 and call and call.ret==addr and cpu.state.PC.value==addr+1 then
      emit('os-return',{pid=id,service=call.service,pc=addr,x=cpu.state.X.value,y=cpu.state.Y.value,a=cpu.state.A.value,b=cpu.state.B.value,cc=cpu.state.CC.value});pending[id]=nil
     end
    end)
   end
  end)
  local thread=coroutine.create(function()
   while m.time:as_double()-start<p.duration do
    local descriptor=pid and proc(pid);local current=owner();local task=gr:read(1)&1
    local e={pid=pid,current=current,task=task,pc=cpu.state.PC.value}
    e.module,e.module_offset=module_at(e.pc,task)
    if descriptor then
     e.priority=sb(descriptor+10);e.age=sb(descriptor+11);e.state=sb(descriptor+12)
     e.queue=queue(0x52,descriptor) and 'active' or queue(0x54,descriptor) and 'wait' or queue(0x56,descriptor) and 'sleep' or 'none'
     if data_u then
      local function ub(a) return ram:read((sw(descriptor+0x40+2*(a//8192))&255)*8192+a%8192) end
      local target=data_u+p.target_offset
      e.target=((ub(target)*256+ub(target+1))*256+ub(target+2))*256+ub(target+3)
     end
    end
    local s=encode(e)
    -- PC intentionally retained: system-mode stalls need executing address evidence.
    if s~=last then emit('process-sample',e);last=s end
    if not emu.wait(p.interval_us/1000000) then emit('discontinuity');break end
   end
   for _,tap in ipairs(taps) do tap:remove() end;active=false;m.video.throttled=true
   local f=assert(io.open(p.path,'w'));f:write(encode({start=start,finish=m.time:as_double(),events=array(events),droppedEvents=dropped,config=p,modules=modules}));f:close()
  end)
  local ok,err=coroutine.resume(thread);assert(ok,err);return {started=true}
 end
 commands.scheduling_status=function() return {active=active} end
end
