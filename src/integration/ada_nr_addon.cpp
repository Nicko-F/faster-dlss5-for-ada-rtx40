// Opt-in 145 buffer routes, with optional guarded Pre/Post (mode 2).
// Intercept the selected NR module through its exports and observed call contracts.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <bcrypt.h>
#include <atomic>
#include <cstdio>
#include <string>
#include <vector>
#include <unordered_map>
#include <shared_mutex>
#include <mutex>
#include <iterator>
#include <nvsdk_ngx_params.h>
#include "../optimization/dynamic_contract.h"

#include "ada_nr_api.h"

namespace ada_game {
struct Descriptor {void *function;unsigned grid[3],block[3],shared,reserved;const void *params;unsigned bytes,reserved2;};
static_assert(sizeof(Descriptor)==56 && offsetof(Descriptor,params)==40);
using Module=int(__cdecl *)(void*,const void*,unsigned,void**);
using Create=int(__cdecl *)(void*,void*,const char*,void**);
using Launch=int(__cdecl *)(ID3D12GraphicsCommandList*,const Descriptor*,unsigned);
using Query=void*(__cdecl *)(unsigned);
static std::atomic<Module> originalModule{};
static std::atomic<Create> originalCreate{};
static std::atomic<Launch> originalLaunch{};
static std::atomic<Query> originalQuery{};
static FARPROC(WINAPI *originalGetProc)(HMODULE,LPCSTR)=GetProcAddress;
struct Entry {std::string name;std::vector<void*> candidates;void *frontback=nullptr;};
struct SurfaceImage {const char *name,*filename,*sha;std::vector<unsigned char> data;};
static SurfaceImage surfaceImages[]{
    {nr_compat::profile.surfaces[0].name,nr_compat::profile.surfaces[0].filename,nr_compat::profile.surfaces[0].sha,{}},
    {nr_compat::profile.surfaces[1].name,nr_compat::profile.surfaces[1].filename,nr_compat::profile.surfaces[1].sha,{}}};
static std::unordered_map<void*,Entry> functions;
static std::vector<unsigned char> images[std::size(integrated::images)];
static std::shared_mutex functionsMutex;
static std::mutex initMutex,logMutex,adapterMutex;
static bool initialized=false,enabled=false;
static std::atomic<bool> ready{false};
static bool explicitHost=true;
static std::wstring initializedBundle,initializedRuntime;
static unsigned initializedMode=0;
static bool surfaceEnabled=false;
static HMODULE nrModule=nullptr;
using Evaluate=NVSDK_NGX_Result(NVSDK_CONV *)(ID3D12GraphicsCommandList*,const NVSDK_NGX_Handle*,const NVSDK_NGX_Parameter*,PFN_NVSDK_NGX_ProgressCallback_C);
static std::atomic<Evaluate> originalEvaluate{};
static FARPROC(WINAPI *originalPluginGetProc)(HMODULE,LPCSTR)=GetProcAddress;
struct OutputScope {ID3D12GraphicsCommandList *list=nullptr;bool valid=false;unsigned format=0,width=0,height=0;};
static thread_local OutputScope outputScope;
static FILE *log=nullptr,*frames=nullptr;
static std::atomic<unsigned> graphs{0};
static std::atomic<bool> contractQualified{false};
static std::atomic<unsigned> evaluations{0};
struct Graph {unsigned slot=156,replaced=0,guardFailed=0,errors=0,width=0,height=0;ID3D12GraphicsCommandList *list=nullptr;
    unsigned frontback=0,surfaceFailed=0,historyNative=0,outputFormat=0,surfaceValid=0;bool authorized=false,optimize=false;
    nr_dynamic::Shape shape{};
};
static thread_local Graph graph;

static bool OutputValid(const D3D12_RESOURCE_DESC &d) {
    return nr_compat::OutputValid(d.Format,d.Width,d.Height,d.Dimension,d.MipLevels,d.DepthOrArraySize,d.SampleDesc.Count);
}
__declspec(noinline) static void ObserveOutput(ID3D12GraphicsCommandList *list,const NVSDK_NGX_Parameter *params) {
    outputScope={};outputScope.list=list;graph={}; // A fresh Evaluate invalidates any incomplete graph.
    int preset=-1,flags=-1;
    const bool presetKnown=params && NVSDK_NGX_SUCCEED(params->Get("DLSSNR.Hint.Render.Preset",&preset));
    const bool flagsKnown=params && NVSDK_NGX_SUCCEED(params->Get("DLSS.Feature.Create.Flags",&flags));
    const bool profileValid=presetKnown && flagsKnown && nr_compat::ParametersValid(preset,flags);
    ID3D12Resource *output=nullptr;
    // NR-specific binding used by the community game path; the laboratory
    // also publishes the generic Output alias.
    auto status=params?params->Get("DLSSNR.Output",&output):NVSDK_NGX_Result_FAIL_InvalidParameter;
    if(params && (!NVSDK_NGX_SUCCEED(status) || !output))status=params->Get("Output",&output);
    if(NVSDK_NGX_SUCCEED(status) && output) {
        const auto desc=output->GetDesc();outputScope.valid=profileValid && OutputValid(desc);outputScope.format=desc.Format;
        outputScope.width=static_cast<unsigned>(desc.Width);outputScope.height=desc.Height;
    }
    if(evaluations.fetch_add(1)<3) {std::lock_guard<std::mutex> lock(logMutex);
        std::fprintf(log,"output_binding,%lu,%p,%u,%p,%u,%u,preset,%d,flags,%d\n",GetCurrentThreadId(),list,status,output,outputScope.format,outputScope.valid,preset,flags);std::fflush(log);}
}
static NVSDK_NGX_Result NVSDK_CONV EvaluateFeature(ID3D12GraphicsCommandList *list,const NVSDK_NGX_Handle *handle,
    const NVSDK_NGX_Parameter *params,PFN_NVSDK_NGX_ProgressCallback_C callback) {
    ObserveOutput(list,params);
    // Keep this a tail call: the signed runtime must retain the caller's
    // original return address. Build assembly is audited for JMP, not CALL.
    return originalEvaluate.load()(list,handle,params,callback);
}

static bool ReadImage(const std::wstring &path,const char *expected,std::vector<unsigned char> &data,long maxBytes=64*1024*1024) {
    FILE *f=nullptr;if(_wfopen_s(&f,path.c_str(),L"rb"))return false;
    std::fseek(f,0,SEEK_END);long n=std::ftell(f);std::rewind(f);
    if(n<=0 || n>maxBytes){std::fclose(f);return false;}
    data.resize(n);bool ok=std::fread(data.data(),1,data.size(),f)==data.size();std::fclose(f);
    BCRYPT_ALG_HANDLE a=nullptr;BCRYPT_HASH_HANDLE h=nullptr;unsigned char digest[32];
    ok=ok && BCryptOpenAlgorithmProvider(&a,BCRYPT_SHA256_ALGORITHM,nullptr,0)==0;
    ok=ok && BCryptCreateHash(a,&h,nullptr,0,nullptr,0,0)==0;
    ok=ok && BCryptHashData(h,data.data(),static_cast<ULONG>(data.size()),0)==0;
    ok=ok && BCryptFinishHash(h,digest,32,0)==0;
    if(h)BCryptDestroyHash(h);if(a)BCryptCloseAlgorithmProvider(a,0);
    if(!ok)return false;char hex[65]{};for(unsigned i=0;i<32;++i)sprintf_s(hex+2*i,3,"%02x",digest[i]);
    return std::strcmp(hex,expected)==0;
}
static int __cdecl CreateKernel(void *device,void *module,const char *name,void **out) {
    const int status=originalCreate.load()(device,module,name,out);
    if(status || !name || !out || !*out)return status;
    Entry e;e.name=name;e.candidates.resize(std::size(integrated::images));
    for(unsigned i=0;i<std::size(integrated::images);++i) if(e.name==integrated::images[i].name) {
        void *candidateModule=nullptr,*function=nullptr;
        const auto make=originalModule.load();
        if(!make || make(device,images[i].data(),static_cast<unsigned>(images[i].size()),&candidateModule) || !candidateModule ||
           originalCreate.load()(device,candidateModule,name,&function) || !function || function==*out) {
            std::lock_guard<std::mutex> lock(logMutex);std::fprintf(log,"candidate_create_failed,%u\n",i);std::fflush(log);
        } else e.candidates[i]=function;
    }
    if(surfaceEnabled) for(auto &s:surfaceImages) if(e.name==s.name) {
        void *candidateModule=nullptr,*function=nullptr;const auto make=originalModule.load();
        if(!make || make(device,s.data.data(),static_cast<unsigned>(s.data.size()),&candidateModule) || !candidateModule ||
           originalCreate.load()(device,candidateModule,name,&function) || !function || function==*out) {
            std::lock_guard<std::mutex> lock(logMutex);std::fprintf(log,"surface_create_failed,%s\n",name);std::fflush(log);
        } else e.frontback=function;
    }
    std::unique_lock<std::shared_mutex> lock(functionsMutex);functions[*out]=std::move(e);return status;
}
static int __cdecl LaunchKernel(ID3D12GraphicsCommandList *list,const Descriptor *d,unsigned count) {
    const auto launch=originalLaunch.load();
    if(!list || !d || count!=1){graph={};outputScope={};return launch(list,d,count);}
    std::shared_lock<std::shared_mutex> lock(functionsMutex);
    const auto found=functions.find(d->function);
    if(found==functions.end())return launch(list,d,count);
    const auto &entry=found->second;
    // Other features (e.g. SR) may dispatch after a completed NR graph.
    // They cannot invalidate a contract that was qualified inside Evaluate NR.
    if(graph.slot>=156 && entry.name!=integrated::sequence[0])return launch(list,d,count);
    if(entry.name==integrated::sequence[0]) {graph={};graph.slot=0;graph.list=list;
        graph.optimize=enabled && contractQualified.load();
        graph.authorized=outputScope.list==list && outputScope.valid;graph.outputFormat=outputScope.format;
        graph.width=outputScope.width;graph.height=outputScope.height;
        outputScope={}; // One Evaluate binding can authorize at most one graph.
        if(surfaceEnabled && graphs.load()<3) {std::lock_guard<std::mutex> write(logMutex);
            std::fprintf(log,"graph_binding,%lu,%p,%u,%u\n",GetCurrentThreadId(),list,graph.authorized,graph.outputFormat);std::fflush(log);}}
    if(graph.slot>=156 || graph.list!=list || entry.name!=integrated::sequence[graph.slot]) {
        contractQualified=false;graph.slot=156;outputScope={};std::lock_guard<std::mutex> write(logMutex);
        std::fprintf(log,"sequence_fallback,%s\n",entry.name.c_str());std::fflush(log);return launch(list,d,count);
    }
    if(graph.slot==1 && d->params && d->bytes==264) {
        graph.authorized=graph.authorized && nr_dynamic::FromPre(graph.width,graph.height,d->params,d->bytes,graph.shape);
        if(graph.authorized){graph.width=graph.shape.width;graph.height=graph.shape.height;}

    }
    Descriptor chosen=*d;
    if(surfaceEnabled && (graph.slot==1 || graph.slot==154)) {
        const bool binding=graph.authorized;
        const bool abi=d->params && d->bytes==(graph.slot==1?264u:184u);
        unsigned long long history=0,mv=0;
        if(abi) {const auto p=static_cast<const unsigned char*>(d->params);
            std::memcpy(&history,p+(graph.slot==1?8:88),8);std::memcpy(&mv,p+(graph.slot==1?16:96),8);}
        const bool valid=frontback::Valid(graph.slot,graph.shape,d->grid,d->block,d->shared,d->reserved,d->reserved2,d->params,d->bytes);

        if(binding && valid && entry.frontback) {++graph.surfaceValid;if(graph.optimize){chosen.function=entry.frontback;++graph.frontback;}}
        else if(binding && abi && (!history || !mv)) ++graph.historyNative;
        else ++graph.surfaceFailed;
    }
    for(const auto &route:integrated::routes) if(route.slot==graph.slot) {
        const bool valid=graph.authorized &&
            integrated::Valid(route,graph.shape,d->grid,d->block,d->shared,d->reserved,d->reserved2,d->params,d->bytes);
        const auto candidate=entry.candidates[valid?integrated::ImageFor(route,graph.shape,d->params):route.newImage];

        if(!valid || !candidate)++graph.guardFailed;
        if(valid && candidate && graph.optimize) {chosen.function=candidate;++graph.replaced;}
        break;
    }
    const int status=launch(list,&chosen,1);if(status)++graph.errors;
    if(++graph.slot==156) {
        outputScope={}; // A binding authorizes this graph only.
        const bool qualified=graph.authorized && !graph.guardFailed && !graph.surfaceFailed && !graph.errors &&
            (!surfaceEnabled || graph.surfaceValid==2);
        if(qualified)contractQualified=true;
        const unsigned index=graphs.fetch_add(1);
        std::lock_guard<std::mutex> write(logMutex);
        std::fprintf(frames,"%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",index,graph.optimize,graph.replaced,graph.guardFailed,graph.errors,graph.width,graph.height,
            graph.frontback,graph.surfaceFailed,graph.historyNative,graph.outputFormat,enabled && !graph.optimize,qualified);
        if(index<3 || index%60==0)std::fflush(frames);
    }
    return status;
}
static void* __cdecl QueryInterface(unsigned id) {
    void *p=originalQuery.load()(id);
    if(p && id==0xad1a677d)originalModule=reinterpret_cast<Module>(p);
    if(p && id==0xe2436e22){originalCreate=reinterpret_cast<Create>(p);return reinterpret_cast<void*>(&CreateKernel);}
    if(p && id==0x24973538){originalLaunch=reinterpret_cast<Launch>(p);return reinterpret_cast<void*>(&LaunchKernel);}
    return p;
}
static FARPROC WINAPI GetProc(HMODULE module,LPCSTR name) {
    FARPROC p=originalGetProc(module,name);
    if(p && reinterpret_cast<uintptr_t>(name)>0xffff && !std::strcmp(name,"nvapi_QueryInterface")) {
        originalQuery=reinterpret_cast<Query>(p);return reinterpret_cast<FARPROC>(&QueryInterface);
    }
    return p;
}
static FARPROC WINAPI PluginGetProc(HMODULE module,LPCSTR name) {
    FARPROC p=originalPluginGetProc(module,name);
    if(p && module==nrModule && reinterpret_cast<uintptr_t>(name)>0xffff && !std::strcmp(name,"NVSDK_NGX_D3D12_EvaluateFeature")) {
        originalEvaluate=reinterpret_cast<Evaluate>(p);
        std::lock_guard<std::mutex> lock(logMutex);std::fprintf(log,"evaluate_hook,1\n");std::fflush(log);
        return reinterpret_cast<FARPROC>(&EvaluateFeature);
    }
    return p;
}
static bool Hook(HMODULE module,bool plugin=false) {
    auto b=reinterpret_cast<unsigned char*>(module);auto dos=reinterpret_cast<IMAGE_DOS_HEADER*>(b);
    auto nt=reinterpret_cast<IMAGE_NT_HEADERS64*>(b+dos->e_lfanew);
    const auto rva=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    if(!rva)return false;
    for(auto m=reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(b+rva);m->Name;++m) {
        if(_stricmp(reinterpret_cast<char*>(b+m->Name),"KERNEL32.dll") || !m->OriginalFirstThunk)continue;
        auto names=reinterpret_cast<IMAGE_THUNK_DATA64*>(b+m->OriginalFirstThunk);
        auto slots=reinterpret_cast<IMAGE_THUNK_DATA64*>(b+m->FirstThunk);
        for(;names->u1.AddressOfData;++names,++slots) {
            if(IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal))continue;
            auto n=reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(b+names->u1.AddressOfData);
            if(std::strcmp(reinterpret_cast<char*>(n->Name),"GetProcAddress"))continue;
            auto target=reinterpret_cast<void**>(&slots->u1.Function);DWORD old;
            if(!VirtualProtect(target,sizeof(void*),PAGE_READWRITE,&old))return false;
            if(plugin)originalPluginGetProc=reinterpret_cast<decltype(originalPluginGetProc)>(*target);
            else originalGetProc=reinterpret_cast<decltype(originalGetProc)>(*target);
            void *previous=*target;
            InterlockedExchangePointer(target,plugin?reinterpret_cast<void*>(&PluginGetProc):reinterpret_cast<void*>(&GetProc));DWORD ignored;
            if(VirtualProtect(target,sizeof(void*),old,&ignored))return true;
            InterlockedExchangePointer(target,previous);VirtualProtect(target,sizeof(void*),old,&ignored);
            return false;
        }
    }return false;
}
static bool AbsolutePath(const wchar_t *path) {
    return path && std::wcslen(path)>2 &&
        ((path[1]==L':' && (path[2]==L'\\' || path[2]==L'/')) || (path[0]==L'\\' && path[1]==L'\\'));
}
static bool ConfigValid(const AdaNrConfigV1 *config) {
    return config && config->structBytes==sizeof(AdaNrConfigV1) && config->version==1 && config->mode<=2 &&
        AbsolutePath(config->bundlePath) && AbsolutePath(config->runtimePath);
}
static bool Initialize(const AdaNrConfigV1 *config,bool fromExplicitHost=true) {
    if(!ConfigValid(config))return false;
    std::lock_guard<std::mutex> init(initMutex);
    if(initialized)return ready.load() && initializedBundle==config->bundlePath && initializedRuntime==config->runtimePath &&
        initializedMode==config->mode && explicitHost==fromExplicitHost;
    struct Attempt {
        bool committed=false;
        ~Attempt(){if(!committed){if(log)std::fclose(log);if(frames)std::fclose(frames);log=frames=nullptr;
            if(nrModule)FreeLibrary(nrModule);nrModule=nullptr;}}
    } attempt;
    const std::wstring folder=config->bundlePath;
    if(_wfopen_s(&log,(folder+L"/ada-nr-events.log").c_str(),L"wb") ||
       _wfopen_s(&frames,(folder+L"/ada-nr-frames.csv").c_str(),L"wb"))return false;
    std::fprintf(frames,"graph,optimized,replaced,guard_failed,launch_errors,width,height,frontback,surface_failed,history_native,output_format,qualification,contract_qualified\n");
    const unsigned choice=config->mode;enabled=choice!=0;surfaceEnabled=choice==2;
    std::fprintf(log,"profile,%s\n",nr_compat::profile.id);
    if(surfaceEnabled) for(auto &s:surfaceImages) {
        const std::string name=s.filename;
        if(!ReadImage(folder+L"/"+std::wstring(name.begin(),name.end()),s.sha,s.data)) {
            std::fprintf(log,"surface_identity_failed,%s\n",s.name);std::fflush(log);return false;
        }
    }
    for(unsigned i=0;i<std::size(integrated::images);++i) {
        const auto &image=integrated::images[i];std::string name=image.filename;
        if(!ReadImage(folder+L"/"+std::wstring(name.begin(),name.end()),image.sha,images[i])) {
            std::fprintf(log,"image_identity_failed,%u\n",i);std::fflush(log);return false;
        }
    }
    HMODULE self=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(&Initialize),&self))return false;
    nrModule=LoadLibraryExW(config->runtimePath,nullptr,LOAD_WITH_ALTERED_SEARCH_PATH);
    // Whole-file hashes identify test evidence, not runtime compatibility.
    // Verify the selected module was loaded and exposes the integration entry point.
    wchar_t actual[32768]{},requested[32768]{};
    const auto actualLength=nrModule?GetModuleFileNameW(nrModule,actual,32768):0;
    const auto requestedLength=GetFullPathNameW(config->runtimePath,32768,requested,nullptr);
    if(!actualLength || actualLength>=32768 || !requestedLength || requestedLength>=32768 ||
       _wcsicmp(actual,requested) || !GetProcAddress(nrModule,"NVSDK_NGX_D3D12_EvaluateFeature")) {
        std::fprintf(log,"runtime_interface_failed\n");std::fflush(log);return false;
    }
    initializedBundle=config->bundlePath;initializedRuntime=config->runtimePath;initializedMode=config->mode;
    explicitHost=fromExplicitHost;
    const bool ok=nrModule && Hook(nrModule);
    if(ok){attempt.committed=true;initialized=true;ready=true;}
    std::fprintf(log,"hook,%u,mode,%u,surface_candidates,%u\n",ok,choice,surfaceEnabled);std::fflush(log);
    return ok;
}
// Existing community caller adapter. Other hosts use the explicit V1 API below.
static void InitDevice(void*) {
    std::lock_guard<std::mutex> adapter(adapterMutex);if(ready.load())return;
    wchar_t path[32768]{};HMODULE self=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&InitDevice),&self))return;
    const auto length=GetModuleFileNameW(self,path,32768);if(!length || length>=32768)return;
    const std::wstring imagePath=path;const auto slash=imagePath.find_last_of(L"/\\");
    if(slash==std::wstring::npos)return;
    const std::wstring directory=imagePath.substr(0,slash+1);
    const auto n=GetEnvironmentVariableW(L"ADA_NR_BUNDLE",path,32768);if(n>=32768)return;
    const std::wstring folder=n?std::wstring(path):directory+L"faster-dlss5/profiles/automatic/bundle";
    FILE *mode=nullptr;unsigned choice=2;char extra;
    if(_wfopen_s(&mode,(folder+L"/mode.txt").c_str(),L"rb"))return;
    const int fields=fscanf_s(mode,"%u %c",&choice,&extra,1u);std::fclose(mode);if(fields!=1 || choice>2)return;
    const std::wstring runtime=directory+L"nvngx_dlssnr.dll";
    const AdaNrConfigV1 config{sizeof(AdaNrConfigV1),1,folder.c_str(),runtime.c_str(),choice};
    if(!Initialize(&config,false))return;
    if(enabled) {
        const auto plugin=GetModuleHandleW(L"renodx-dlss5.addon64");
        if(!plugin || !Hook(plugin,true)) {
            std::fprintf(log,"plugin_evaluate_hook_failed\n");
        }
    }
    std::fflush(log);
}
}
extern "C" __declspec(dllexport) BOOL WINAPI AdaNrInitializeV1(const AdaNrConfigV1 *config) {
    return ada_game::Initialize(config)?TRUE:FALSE;
}
extern "C" __declspec(dllexport) FARPROC WINAPI AdaNrGetEvaluateV1(HMODULE runtime) {
    using namespace ada_game;
    if(!ready.load() || !runtime || runtime!=nrModule)return nullptr;
    auto proc=GetProcAddress(runtime,"NVSDK_NGX_D3D12_EvaluateFeature");
    if(!proc)return nullptr;
    originalEvaluate=reinterpret_cast<Evaluate>(proc);
    return reinterpret_cast<FARPROC>(&EvaluateFeature);
}
extern "C" __declspec(dllexport) const char* WINAPI AdaNrProfileV1() {return nr_compat::profile.id;}
extern "C" __declspec(dllexport) const char *NAME="Faster DLSS5 for Ada / RTX 40";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Profile-checked NR buffer and Pre/Post optimization; explicit host API or community adapter.";
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,void*) {
    if(reason==DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        HMODULE reshade=nullptr;
        for(const auto name:{L"dxgi.dll",L"d3d11.dll",L"d3d9.dll",L"opengl32.dll",L"ReShade64.dll"}) {
            const auto candidate=GetModuleHandleW(name);
            if(candidate && GetProcAddress(candidate,"ReShadeRegisterAddon")){reshade=candidate;break;}
        }
        auto reg=reinterpret_cast<bool(*)(void*,unsigned)>(GetProcAddress(reshade,"ReShadeRegisterAddon"));
        auto event=reinterpret_cast<void(*)(unsigned,void*)>(GetProcAddress(reshade,"ReShadeRegisterEvent"));
        // ReShade 6.8 / API 18: init_device is event 0; no C++ device vtable is used.
        if(reg && event) {
            if(!reg(instance,18))return FALSE;
            event(0,reinterpret_cast<void*>(&ada_game::InitDevice));
        } // Hosts without ReShade initialize explicitly after LoadLibrary returns.
    }
    if(reason==DLL_PROCESS_DETACH) {if(ada_game::frames)std::fflush(ada_game::frames);if(ada_game::log)std::fflush(ada_game::log);}
    return TRUE;
}
