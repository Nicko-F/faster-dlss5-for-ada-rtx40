#include "../../src/integration/ada_nr_addon.cpp"
#include <cassert>
static const void *lastParams=nullptr;
static void *lastFunction=nullptr;
static int __cdecl FakeLaunch(ID3D12GraphicsCommandList*,const ada_game::Descriptor *d,unsigned) {
    lastParams=d->params;lastFunction=d->function;return 0;
}
// Synthetic ABI fixtures: values model the captured field roles, not replay data.
static void Put32(unsigned char *p,unsigned offset,unsigned value) {std::memcpy(p+offset,&value,4);}
static void Put64(unsigned char *p,unsigned offset,unsigned long long value) {std::memcpy(p+offset,&value,8);}
static void PutFloat(unsigned char *p,unsigned offset,float value) {Put32(p,offset,nr_dynamic::FloatBits(value));}
static void PutActiveUv(unsigned char *p,unsigned extentOffset,unsigned scaleOffset,const nr_dynamic::Shape &s) {
    PutFloat(p,extentOffset,static_cast<float>(s.width));PutFloat(p,extentOffset+4,static_cast<float>(s.height));
    PutFloat(p,scaleOffset,1.0f/static_cast<float>(s.width));PutFloat(p,scaleOffset+4,1.0f/static_cast<float>(s.height));
}
static void FillSurface(unsigned slot,const nr_dynamic::Shape &s,unsigned char *p,ada_game::Descriptor &d) {
    std::memset(p,0,264);d.bytes=slot==1?264:184;d.shared=d.reserved=d.reserved2=0;
    d.block[0]=32;d.block[1]=d.block[2]=1;d.grid[0]=s.paddedWidth/8+(slot==154);
    d.grid[1]=s.paddedHeight/8+(slot==154);d.grid[2]=1;
    if(slot==1) {
        Put64(p,0,0x101);Put64(p,8,0x103);Put64(p,16,0x105);
        PutActiveUv(p,48,56,s);PutActiveUv(p,72,80,s);PutActiveUv(p,144,152,s);
        PutFloat(p,160,1.0f/static_cast<float>(s.width));PutFloat(p,164,1.0f/static_cast<float>(s.height));
        Put32(p,168,1);PutFloat(p,172,1.0f);PutFloat(p,176,1.0f);PutFloat(p,184,1.0f);PutFloat(p,188,1.0f);
        Put32(p,192,1);PutFloat(p,196,0.0625f);Put32(p,200,20);
        Put32(p,208,s.height);Put32(p,212,s.width);Put64(p,216,0x10000);Put64(p,224,0x11000);
        Put32(p,240,s.paddedHeight);Put32(p,244,s.paddedWidth);Put64(p,248,0x12000);
        Put32(p,256,s.paddedHeight/2);Put32(p,260,s.paddedWidth/2);
    } else {
        Put64(p,0,0x10000);Put64(p,8,0x11000);Put64(p,16,0x113);Put64(p,24,0x12000);
        Put32(p,32,s.paddedHeight);Put32(p,36,s.paddedWidth);Put32(p,40,0xfffffffcu);Put32(p,44,0xfffffffcu);
        PutFloat(p,48,0.03125f);Put32(p,52,1);Put64(p,56,0x117);PutActiveUv(p,72,80,s);
        Put64(p,88,0x119);Put64(p,96,0x11b);Put64(p,104,0x13000);Put32(p,112,1);
        PutActiveUv(p,124,132,s);PutActiveUv(p,148,156,s);
        PutFloat(p,164,1.0f/static_cast<float>(s.width));PutFloat(p,168,1.0f/static_cast<float>(s.height));
        Put32(p,172,s.width);Put32(p,176,s.height);
    }
}
static bool SurfaceValid(unsigned slot,const nr_dynamic::Shape &s,const unsigned char *p,const ada_game::Descriptor &d) {
    return frontback::Valid(slot,s,d.grid,d.block,d.shared,d.reserved,d.reserved2,p,d.bytes);
}
static void CheckSurfaceGuards() {
    const nr_dynamic::Shape s{1919,1199,1920,1216};unsigned char p[264]{};ada_game::Descriptor d{};
    FillSurface(1,s,p,d);assert(SurfaceValid(1,s,p,d));
    Put32(p,200,0xa5a55a5a);PutFloat(p,172,0.75f);Put64(p,24,0x121);PutFloat(p,40,0.25f);
    assert(SurfaceValid(1,s,p,d)); // forwarded controls and optional resources are not folded
    Put64(p,8,0);assert(!SurfaceValid(1,s,p,d));Put64(p,8,0x103);
    PutFloat(p,48,1280.0f);PutFloat(p,52,800.0f);PutFloat(p,56,1.0f/1280.0f);PutFloat(p,60,1.0f/800.0f);
    assert(SurfaceValid(1,s,p,d)); // native mappings need not equal the active output shape
    Put32(p,56,0x7fc00000u);assert(!SurfaceValid(1,s,p,d));PutFloat(p,56,1.0f/1280.0f);
    Put64(p,216,0);assert(!SurfaceValid(1,s,p,d));Put64(p,216,0x10000);
    ++d.grid[0];assert(!SurfaceValid(1,s,p,d));--d.grid[0];assert(SurfaceValid(1,s,p,d));

    FillSurface(154,s,p,d);assert(SurfaceValid(154,s,p,d));
    Put64(p,104,0);assert(SurfaceValid(154,s,p,d)); // Native default blend weight is valid.
    Put32(p,48,0x3d800000u);Put32(p,52,0);Put64(p,56,0);Put32(p,112,0);PutFloat(p,116,0.5f);
    assert(SurfaceValid(154,s,p,d)); // native decode/motion controls remain live inputs
    Put64(p,96,0);assert(!SurfaceValid(154,s,p,d));Put64(p,96,0x11b);
    PutFloat(p,128,800.0f);PutFloat(p,136,1.0f/800.0f);assert(SurfaceValid(154,s,p,d));
    PutFloat(p,136,0.0f);assert(!SurfaceValid(154,s,p,d));PutFloat(p,136,1.0f/800.0f);
    Put64(p,16,0);assert(!SurfaceValid(154,s,p,d));Put64(p,16,0x113);
    ++d.grid[1];assert(!SurfaceValid(154,s,p,d));--d.grid[1];assert(SurfaceValid(154,s,p,d));
}
int main() {
    using namespace ada_game;
    CheckSurfaceGuards();
    fopen_s(&ada_game::log,"dynamic-test-events.log","wb");fopen_s(&frames,"dynamic-test-frames.csv","wb");
    assert(ada_game::log && frames);originalLaunch=FakeLaunch;enabled=surfaceEnabled=true;explicitHost=true;
    auto list=reinterpret_cast<ID3D12GraphicsCommandList*>(0x1000);
    const nr_dynamic::Shape shapes[]={{640,360,640,384},{1920,1080,1920,1152},{2560,1440,2560,1472},
        {3840,2160,3840,2176},{1920,1200,1920,1216},{1600,1000,1600,1024},
        {2560,1600,2560,1600},{3440,1440,3456,1472},{1919,1199,1920,1216},{1920,1080,1920,1152}};
    for(const auto &shape:shapes) {
        const bool qualification=!contractQualified.load();
        const bool noHistory=&shape==&shapes[std::size(shapes)-1];
        assert(nr_dynamic::ValidShape(shape));unsigned dims[7][2];nr_dynamic::Dimensions(shape,dims);
        outputScope={list,true,28,shape.width,shape.height};
        for(unsigned slot=0;slot<156;++slot) {
            void *native=reinterpret_cast<void*>(uintptr_t(0x2000+slot*16));Entry entry;
            entry.name=integrated::sequence[slot];entry.candidates.resize(std::size(integrated::images));entry.frontback=reinterpret_cast<void*>(0xa000);
            for(unsigned i=0;i<entry.candidates.size();++i)entry.candidates[i]=reinterpret_cast<void*>(uintptr_t(0x9000+i*16));
            functions[native]=entry;unsigned char p[264]{};Descriptor d{};d.function=native;d.params=p;
            const integrated::Route *selected=nullptr;
            for(const auto &r:integrated::routes)if(r.slot==slot) {
                selected=&r;d.bytes=r.bytes;d.shared=r.shared;std::memcpy(d.block,r.block,sizeof(d.block));std::memcpy(p,r.literal,r.bytes);
                for(unsigned i=0;i<r.dimCount;++i){const auto &f=r.dims[i];std::memcpy(p+f.offset,&dims[f.level][f.axis],4);}
                for(unsigned word=0;word<12;++word)if(r.pointerMask&(1u<<word)) {UINT64 v=0x10000+word*256;std::memcpy(p+word*8,&v,8);}
                auto h=dims[r.level][0],w=dims[r.level][1];d.grid[2]=r.grid[2];
                if(r.gridKind==0){d.grid[0]=r.gridMultiplier*((w+r.gridBias[0]+7)/8);d.grid[1]=(h+r.gridBias[1]+7)/8;}
                else if(r.gridKind==1){d.grid[0]=r.gridMultiplier*((h*w+127)/128);d.grid[1]=1;}
                else {d.grid[0]=32;d.grid[1]=(h*w+255)/256;d.grid[2]=1;}
                assert(integrated::Valid(r,shape,d.grid,d.block,d.shared,0,0,p,d.bytes));
                ++d.grid[0];assert(!integrated::Valid(r,shape,d.grid,d.block,d.shared,0,0,p,d.bytes));--d.grid[0];
                ++p[r.dims[0].offset];assert(!integrated::Valid(r,shape,d.grid,d.block,d.shared,0,0,p,d.bytes));--p[r.dims[0].offset];
            }
            if(slot==1 || slot==154) {
                FillSurface(slot,shape,p,d);
                if(noHistory && slot==1)Put64(p,8,0);
            }
            unsigned char unchanged[264];std::memcpy(unchanged,p,sizeof(p));const Descriptor before=d;
            assert(LaunchKernel(list,&d,1)==0 && lastParams==p && !std::memcmp(p,unchanged,sizeof(p)) && !std::memcmp(&before,&d,sizeof(d)));
            const auto expected=qualification?native:slot==1 || slot==154?(noHistory && slot==1?native:entry.frontback):selected?entry.candidates[integrated::ImageFor(*selected,shape,p)]:native;
            assert(lastFunction==expected);
        }
        assert(graph.replaced==(qualification?0u:145u) && graph.frontback==(qualification?0u:(noHistory?1u:2u)) && graph.historyNative==(noHistory?1u:0u) &&
               !graph.guardFailed && !graph.errors && !graph.surfaceFailed);
        assert(contractQualified.load());
    }
    Descriptor outside{};outside.function=reinterpret_cast<void*>(0x2010);
    assert(LaunchKernel(list,&outside,1)==0 && contractQualified.load() && lastFunction==outside.function);
    Descriptor begin{};begin.function=reinterpret_cast<void*>(0x2000);outputScope={list,true,28,1920,1080};
    assert(LaunchKernel(list,&begin,1)==0);
    Descriptor wrong{};wrong.function=reinterpret_cast<void*>(0x2020);
    assert(LaunchKernel(list,&wrong,1)==0 && !contractQualified.load() && lastFunction==wrong.function);
    // Binding is consumed once; graph start without Evaluate cannot reuse its shape.
    Descriptor start{};start.function=reinterpret_cast<void*>(0x2000);
    assert(LaunchKernel(list,&start,1)==0 && !graph.authorized);
    nr_dynamic::Shape invalid{1920,1200,1920,1199};assert(!nr_dynamic::ValidShape(invalid));
    assert(!nr_compat::OutputValid(41,1920,1200,3,1,1,1));
    assert(graphs==std::size(shapes));std::fclose(ada_game::log);std::fclose(frames);ada_game::log=frames=nullptr;
}
