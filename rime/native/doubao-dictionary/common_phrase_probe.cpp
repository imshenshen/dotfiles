// Research only. Synthetic staging dictionaries; no live writes or cloud access.
#include <dlfcn.h>
#include <string>
#include <iostream>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>
struct Slice {const void *data;unsigned size;};
template<class T>T sym(void*h,const char*n){auto p=dlsym(h,n);if(!p){std::cerr<<"missing symbol\n";exit(2);}return reinterpret_cast<T>(p);}
int main(int argc,char**argv){
 if(argc!=3)return 64;
 auto h=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!h){std::cerr<<dlerror()<<"\n";return 2;}
 using Load=bool(*)(void*,const std::string&,bool,void*);
 using Add=bool(*)(void*,const std::string&,const std::u16string&,bool,bool,bool,bool);
 using Del=bool(*)(void*,const std::string&,const std::u16string&,bool,bool,bool);
 using Save=int(*)(void*,bool);
 using Count=unsigned(*)(const void*);
 auto load=sym<Load>(h,"_ZN11oime_engine6pinyin16CommonPhraseDict4LoadERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEEbPNS2_6vectorINS_8FdErrMsgENS6_ISC_EEEE");
 auto add=sym<Add>(h,"_ZN11oime_engine6pinyin16CommonPhraseDict3AddERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEERKNS3_IDsNS4_IDsEENS6_IDsEEEEbbbb");
 auto del=sym<Del>(h,"_ZN11oime_engine6pinyin16CommonPhraseDict6RemoveERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEERKNS3_IDsNS4_IDsEENS6_IDsEEEEbbb");
 auto save=sym<Save>(h,"_ZN11oime_engine14CustomDictBase4SaveEb");
 auto count=sym<Count>(h,"_ZNK11oime_engine14CustomDictBase8GetCountEv");
 auto prime=sym<Count>(h,"_ZNK11oime_engine6pinyin16CommonPhraseDict13GetPrimeCountEv");
 auto table=(char*)sym<void*>(h,"_ZTVN11oime_engine6pinyin16CommonPhraseDictE")+16;
 // Version-pinned ABI experiment, NOT a production constructor. Isolated process
 // owns the zero-initialized storage until exit; never apply this to a live app.
 auto object=[&](){void *p=calloc(1,4096);*(void**)p=table;return p;};
 auto key=sym<Slice(*)(const void*,unsigned)>(h,"_ZNK11oime_engine14CustomDictBase6GetKeyEj");
 auto value=sym<Slice(*)(const void*,unsigned)>(h,"_ZNK11oime_engine14CustomDictBase8GetValueEj");
 auto decode=sym<std::u16string(*)(const std::u16string&)>(h,"_ZN11oime_engine13DecryptU16StrERKNSt3__112basic_stringIDsNS0_11char_traitsIDsEENS0_9allocatorIDsEEEE");
 auto attr=sym<Slice(*)(const void*,unsigned)>(h,"_ZNK11oime_engine14CustomDictBase12GetAttributeEj");
 auto deleted=sym<bool(*)(const void*,const Slice&)>(h,"_ZNK11oime_engine6pinyin16CommonPhraseDict18AttributeIsDeletedERKNS_5SliceE");
 #define require(x) do {if(!(x)){std::cerr<<"FAIL: "<<#x<<"\n";return 10;}} while(0)
 void*obj=object();
 auto st=load(obj,std::string(argv[2]),true,nullptr);std::cout<<"load="<<st<<" count="<<count(obj)<<"\n";
 if(!st)return 3;
 const std::string py="rimesyncprobe";const std::u16string a=u"Rime Sync Probe A",b=u"Rime Sync Probe B";
 require(count(obj)==0);
 require(add(obj,py,a,true,true,false,false));require(prime(obj)==1);
 require(save(obj,true)==0);
 require(del(obj,py,a,true,true,false));require(prime(obj)==0);
 require(add(obj,py,b,true,true,false,false));require(prime(obj)==1);
 require(save(obj,true)==0);
 void*reloaded=object();require(load(reloaded,std::string(argv[2]),false,nullptr));
 std::cout<<"reloadedCount="<<count(reloaded)<<" prime="<<prime(reloaded)<<"\n";
 require(count(reloaded)==1 && prime(reloaded)==1);
 unsigned active=0,tombstones=0;
 for(unsigned i=0;i<count(reloaded);++i){
   auto k=key(reloaded,i),at=attr(reloaded,i);
   require(k.size==py.size() && memcmp(k.data,py.data(),k.size)==0);
   require(at.size==20);
   auto v=value(reloaded,i);require(v.size%2==0);
   std::u16string encoded((const char16_t*)v.data,v.size/2);require(decode(encoded)==b);
   if(deleted(reloaded,at))++tombstones;else ++active;
 }
 require(active==1 && tombstones==0);
 require(del(reloaded,py,b,true,true,false));require(save(reloaded,true)==0);
 void*final=object();require(load(final,std::string(argv[2]),false,nullptr));
 require(prime(final)==0 && count(final)==0);
 std::cout<<"PASS: add/query/update-as-remove-add/delete/save/reload; native save compacts removed entries\n";
}
