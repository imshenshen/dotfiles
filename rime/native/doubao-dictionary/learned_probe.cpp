// Research only. Synthetic staging dictionaries; no live writes or cloud access.
#include <dlfcn.h>
#include <string>
#include <vector>
#include <iostream>
#include <cstdlib>
#include <array>
#include <cstring>
#include <filesystem>
template<class T>T sym(void*h,const char*n){auto p=dlsym(h,n);if(!p)exit(2);return reinterpret_cast<T>(p);}
struct Slice{const void* p;unsigned n;};
int main(int argc,char**argv){if(argc!=3)return 64;
 auto h=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!h)return 2;
 using Load=bool(*)(void*,const std::string&,bool,void*);
 auto load=sym<Load>(h,"_ZN11oime_engine6pinyin7UsrDict4LoadERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEEbPNS2_6vectorINS_8FdErrMsgENS6_ISC_EEEE");
 using Add=bool(*)(void*,const std::vector<uint16_t>&,const std::string&,const std::u16string&,int);
 auto add=sym<Add>(h,"_ZN11oime_engine6pinyin7UsrDict3AddERKNSt3__16vectorItNS2_9allocatorItEEEERKNS2_12basic_stringIcNS2_11char_traitsIcEENS4_IcEEEERKNS9_IDsNSA_IDsEENS4_IDsEEEENS_16WordInfoFlagTypeE");
 auto save=sym<int(*)(void*,bool,void*)>(h,"_ZN11oime_engine11UsrDictBase4SaveEbPNS_12EventTrackerE");
 auto exp=sym<std::string(*)(const void*)>(h,"_ZNK11oime_engine6pinyin7UsrDict18ExportDictToStringEv");
 auto count=sym<unsigned(*)(const void*)>(h,"_ZNK11oime_engine11UsrDictBase8GetCountEv");
 void*obj=calloc(1,4096);*(void**)obj=(char*)sym<void*>(h,"_ZTVN11oime_engine6pinyin7UsrDictE")+16;
 auto ok=load(obj,std::string(argv[2]),true,nullptr);std::cout<<"load="<<ok<<" count="<<count(obj)<<"\n";if(!ok)return 3;
 std::string py="rimesyncprobe";std::u16string word=u"RimeSyncProbe";std::vector<uint16_t> syll;
 for(char c:py)syll.push_back(10+c-'a');
 if(!add(obj,syll,py,word,0)||count(obj)!=1||save(obj,true,nullptr)!=0)return 10;
 std::cout<<"PASS: native learned-word add/save\n";
 auto txt=exp(obj);if(txt.find("RimeSyncProbe")==std::string::npos)return 11;
 auto attr=sym<void*(*)(const void*,unsigned)>(h,"_ZNK11oime_engine11UsrDictBase12GetAttributeEj")(obj,0);
 std::array<unsigned,4> a{};memcpy(a.data(),attr,16);a[0]=0;
 Slice sl{a.data(),16};auto up=sym<bool(*)(void*,unsigned,const Slice&)>(h,"_ZN11oime_engine11UsrDictBase15UpdateAttributeEjRKNS_5SliceE");
 up(obj,0,sl);txt=exp(obj);
 if(txt.find("RimeSyncProbe")==std::string::npos||save(obj,true,nullptr)!=0)return 12;
 std::cout<<"PASS: zero frequency does not delete exported learned word\n";
 // Real Chinese syllables must use the engine's mapping, not letter IDs or
 // Rime's Wubi codes. Keep this experiment entirely inside the staging folder.
 auto toSyll=sym<bool(*)(const char*,uint16_t,uint16_t&)>(h,"_ZN11oime_engine18PinyinToSyllableIdEPKctRt");
 std::vector<uint16_t> chineseSyll;
 for(const std::string syllable:{"song","shu","qiao","jie","yi"}){
  uint16_t id=0;if(!toSyll(syllable.data(),syllable.size(),id)||!id)return 13;
  chineseSyll.push_back(id);
 }
 if(!add(obj,chineseSyll,"songshuqiaojieyi",u"松鼠桥接乙",0)||count(obj)!=2||save(obj,true,nullptr)!=0)return 14;
 void*reloaded=calloc(1,4096);*(void**)reloaded=*(void**)obj;
 if(!load(reloaded,std::string(argv[2]),false,nullptr)||count(reloaded)!=2)return 15;
 txt=exp(reloaded);
 if(txt.find("松鼠桥接乙")==std::string::npos)return 16;
 std::cout<<"PASS: native Chinese syllable mapping, learned-word add/save/reload/export\n";
 // Follow the same synthetic word into the native upload-control serializer.
 // This still sends nothing and does not establish server deletion semantics.
 sym<void(*)(int)>(h,"_ZN11oime_engine13SetDeviceTypeENS_10DeviceTypeE")(2);
 using Control=std::string(*)(const void*,const void*,unsigned,unsigned&);
 auto control=sym<Control>(h,"_ZN11oime_engine4sync28GenUploadTaskControlPbStreamEPKNS_6pinyin7UsrDictEPKNS1_11UsrSideDictEjRj");
 const auto transport=std::filesystem::path(argv[2])/"transport";
 std::filesystem::create_directory(transport);
 void*single=calloc(1,4096);*(void**)single=*(void**)obj;
 if(!load(single,transport.string(),true,nullptr)||!add(single,chineseSyll,"songshuqiaojieyi",u"松鼠桥接乙",0))return 17;
 unsigned checkpoint=0;
 auto before=control(single,nullptr,0,checkpoint);
 if(before.empty())return 18;
 auto singleAttr=sym<void*(*)(const void*,unsigned)>(h,"_ZNK11oime_engine11UsrDictBase12GetAttributeEj")(single,0);
 memcpy(a.data(),singleAttr,16);a[0]=0;
 up(single,0,sl);
 auto after=control(single,nullptr,0,checkpoint);
 std::cout<<"syntheticUploadBeforeBytes="<<before.size()<<" zeroFrequencyUploadBytes="<<after.size()<<"\n";
 if(after.empty()){
  std::cout<<"OBSERVATION: native upload control omitted the sole zero-frequency word\n";
 }else{
  std::cout<<"OBSERVATION: native upload control remains nonempty after zero frequency; server semantics unverified\n";
 }
}
