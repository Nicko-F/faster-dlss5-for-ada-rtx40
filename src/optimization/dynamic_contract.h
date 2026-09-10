#pragma once
#include <cstring>
#include "dynamic_selection.generated.h"
#include "profile.generated.h"

namespace nr_dynamic {
struct Shape {unsigned width=0,height=0,paddedWidth=0,paddedHeight=0;};
inline unsigned Read32(const void *p,unsigned offset) {unsigned n;std::memcpy(&n,static_cast<const unsigned char*>(p)+offset,4);return n;}
inline unsigned long long Read64(const void *p,unsigned offset) {unsigned long long n;std::memcpy(&n,static_cast<const unsigned char*>(p)+offset,8);return n;}
inline unsigned FloatBits(float value) {unsigned n;std::memcpy(&n,&value,4);return n;}
inline bool PositiveFiniteFloat(const void *p,unsigned offset) {
    const auto bits=Read32(p,offset);return !(bits&0x80000000u) && bits && (bits&0x7f800000u)!=0x7f800000u;
}
inline bool ValidUv(const void *p,unsigned extentOffset,unsigned scaleOffset) {
    return PositiveFiniteFloat(p,extentOffset) && PositiveFiniteFloat(p,extentOffset+4) &&
        PositiveFiniteFloat(p,scaleOffset) && PositiveFiniteFloat(p,scaleOffset+4);
}
inline unsigned Align4(unsigned n) {return (n+3)&~3u;}
inline bool ValidShape(const Shape &s) {
    return s.width && s.height && s.width<=16384 && s.height<=16384 &&
        s.paddedWidth>=s.width && s.paddedHeight>=s.height &&
        s.paddedWidth-s.width<256 && s.paddedHeight-s.height<256 &&
        !(s.paddedWidth%32) && !(s.paddedHeight%32);
}
inline void Dimensions(const Shape &s,unsigned (&d)[7][2]) {
    d[0][0]=s.paddedHeight;d[0][1]=s.paddedWidth;
    for(unsigned level=1;level<=4;++level)for(unsigned axis=0;axis<2;++axis)d[level][axis]=d[0][axis]>>level;
    for(unsigned level=5;level<=6;++level)for(unsigned axis=0;axis<2;++axis)d[level][axis]=Align4((d[level-1][axis]+1)/2);
}
inline bool FromPre(unsigned width,unsigned height,const void *p,unsigned bytes,Shape &s) {
    s={};if(!p || bytes!=264)return false;
    const auto activeH=Read32(p,208),activeW=Read32(p,212);
    if(!activeW || !activeH || activeW>width || activeH>height)return false;
    s={activeW,activeH,Read32(p,244),Read32(p,240)};return ValidShape(s);
}
}
namespace integrated {
inline bool Valid(const Route &r,const nr_dynamic::Shape &shape,const unsigned *grid,const unsigned *block,
                  unsigned shared,unsigned reserved,unsigned reserved2,const void *params,unsigned bytes) {
    if(!nr_dynamic::ValidShape(shape) || !params || bytes!=r.bytes || !grid || !block ||
       reserved || reserved2 || shared!=r.shared || std::memcmp(block,r.block,sizeof(r.block)))return false;
    unsigned dims[7][2];nr_dynamic::Dimensions(shape,dims);
    unsigned char expected[96];std::memcpy(expected,r.literal,sizeof(expected));
    for(unsigned i=0;i<r.dimCount;++i) {const auto &f=r.dims[i];std::memcpy(expected+f.offset,&dims[f.level][f.axis],4);}
    const auto *p=static_cast<const unsigned char*>(params);
    for(unsigned i=0;i<bytes;++i)if(!((r.pointerMask|r.unusedMask)&(1u<<(i/8))) && p[i]!=expected[i])return false;
    for(unsigned word=0;word<12;++word)if(r.pointerMask&(1u<<word)) {
        unsigned long long value=0;std::memcpy(&value,p+word*8,8);if(!value || (value&3))return false;
    }
    const auto h=dims[r.level][0],w=dims[r.level][1];
    unsigned expectedGrid[3]{0,0,r.grid[2]};
    if(r.gridKind==0) {expectedGrid[0]=r.gridMultiplier*((w+r.gridBias[0]+7)/8);expectedGrid[1]=(h+r.gridBias[1]+7)/8;}
    else if(r.gridKind==1) {expectedGrid[0]=r.gridMultiplier*((h*w+127)/128);expectedGrid[1]=1;}
    else {expectedGrid[0]=32;expectedGrid[1]=(h*w+255)/256;expectedGrid[2]=1;}
    return !std::memcmp(grid,expectedGrid,sizeof(expectedGrid));
}
inline unsigned ImageFor(const Route &r,const nr_dynamic::Shape &shape,const void *params) {
    // The original optimized constant folds are selected only for their exact
    // runtime shape AND the already-validated invariant scalar values.
    if(shape.width && shape.height && params)
        for(const auto &s:specializations)if(s.slot==r.slot && s.width==shape.width && s.height==shape.height) {
            const auto *p=static_cast<const unsigned char*>(params);
            // H/W folded by the historical Chained64 variants, not just display dimensions.
            if(nr_dynamic::Read32(p,32)==s.foldedHeight && nr_dynamic::Read32(p,36)==s.foldedWidth)return s.image;
        }
    return static_cast<unsigned>(r.newImage);
}
}
namespace nr_compat {
inline bool ParametersValid(int preset,int flags) {return preset==1 && !(flags&1);}
inline bool OutputValid(unsigned format,unsigned long long width,unsigned height,unsigned dimension,unsigned mips,unsigned layers,unsigned samples) {
    return (format==28 || format==10) && width && width<=16384 && height && height<=16384 && dimension==3 && mips==1 && layers==1 && samples==1;
}
}
namespace frontback {
inline bool Valid(unsigned slot,const nr_dynamic::Shape &s,const unsigned *grid,const unsigned *block,
                  unsigned shared,unsigned reserved,unsigned reserved2,const void *p,unsigned bytes) {
    if((slot!=1 && slot!=154) || !nr_dynamic::ValidShape(s) || !p || bytes!=(slot==1?264u:184u) ||
       !grid || !block || shared || reserved || reserved2 || block[0]!=32 || block[1]!=1 || block[2]!=1 || grid[2]!=1)return false;
    const auto u=[&](unsigned o){return nr_dynamic::Read32(p,o);};
    const auto q=[&](unsigned o){return nr_dynamic::Read64(p,o);};
    const auto buffer=[&](unsigned o){const auto value=q(o);return value && !(value&3);};
    if(slot==1) {
        if(u(208)!=s.height || u(212)!=s.width || u(240)!=s.paddedHeight || u(244)!=s.paddedWidth ||
           u(256)!=s.paddedHeight/2 || u(260)!=s.paddedWidth/2)return false;
        // The retained candidate was qualified on the temporal path. Check its
        // required live resources and the native active-image mappings, but do
        // not constrain forwarded crop offsets, optional depth/mask branches,
        // conditioning controls, or the frame-varying noise seed.
        if(!q(0) || !q(8) || !q(16) || !nr_dynamic::ValidUv(p,48,56) ||
           !nr_dynamic::ValidUv(p,72,80) || !nr_dynamic::ValidUv(p,144,152) ||
           !nr_dynamic::PositiveFiniteFloat(p,160) || !nr_dynamic::PositiveFiniteFloat(p,164) ||
           !buffer(216) || !buffer(224) || !buffer(248))return false;
    } else {
        if(u(32)!=s.paddedHeight || u(36)!=s.paddedWidth || u(40)!=0xfffffffcu || u(44)!=0xfffffffcu ||
           u(172)!=s.width || u(176)!=s.height)return false;
        // Scalar controls and UV offsets remain native inputs. The recompilation
        // did not fold them, so only active-image geometry and required temporal
        // resources belong in this dispatch guard.
        if(!buffer(0) || !buffer(8) || !q(16) || !buffer(24) ||
           (q(56) && !nr_dynamic::ValidUv(p,72,80)) || !q(88) || !q(96) ||
           !nr_dynamic::ValidUv(p,124,132) || !nr_dynamic::ValidUv(p,148,156) ||
           !nr_dynamic::PositiveFiniteFloat(p,164) || !nr_dynamic::PositiveFiniteFloat(p,168))return false;
    }
    const unsigned halo=slot==154?1:0;
    if(grid[0]!=s.paddedWidth/8+halo || grid[1]!=s.paddedHeight/8+halo)return false;
    return true;
}
}
