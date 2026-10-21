// Research only: invoke through tools/research_doubao_dictionary.py, never inside Squirrel.
#include <dlfcn.h>
#include <memory>
#include <string>
#include <iostream>
#include <fstream>
#include <vector>
#include <functional>
#include <array>
#include <set>
#include <algorithm>
int main(int argc,char**argv){
 if(argc!=3 && argc!=4)return 64;
 void*h=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!h){std::cerr<<dlerror()<<"\n";return 2;}
 using Prep=int(*)(const std::string&,std::shared_ptr<const void>&,unsigned long long*,std::string*);
 using Export=std::string(*)(const void*);
 auto prep=(Prep)dlsym(h,"_ZN11oime_engine6pinyin11UsrSideDict15PrepareSnapshotERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEERNS2_10shared_ptrIKS1_EEPyPS8_");
 auto exp=(Export)dlsym(h,"_ZNK11oime_engine6pinyin11UsrSideDict18ExportDictToStringEv");
 if(!prep||!exp)return 3;
 std::shared_ptr<const void> snap;unsigned long long gen=0;std::string path;
 int status=prep(std::string(argv[2]),snap,&gen,&path);
 std::cout<<"status="<<status<<" loaded="<<bool(snap)<<"\n";
 if(status||!snap)return 4;
 struct Item {std::u16string word;std::string input;uint8_t mask;std::vector<std::array<uint8_t,16>> attrs;};
 static_assert(sizeof(Item)==80);
 using Callback=std::function<bool(const std::vector<uint16_t>&,const std::vector<Item>&)>;
 using Visit=bool(*)(const void*,const Callback&);
 auto visit=(Visit)dlsym(h,"_ZNK11oime_engine6pinyin11UsrSideDict5VisitERKNSt3__18functionIFbRKNS2_6vectorItNS2_9allocatorItEEEERKNS4_INS0_15UsrSideDictItemENS5_ISA_EEEEEEE");
 size_t keys=0,words=0,platformAttrs=0;bool containsTest=false,containsMacTest=false,containsPushTest=false;int pushMask=-1;std::set<int> masks;
 struct Fixture {std::vector<uint16_t> key;std::string input;std::u16string word;uint8_t mask;};
 std::vector<Fixture> fixtures;
 Callback cb=[&](const auto& key,const auto& items){++keys;for(auto&it:items){++words;containsTest |= it.word==u"松鼠桥接甲";containsMacTest |= it.word==u"松鼠桥接乙";containsPushTest |= it.word==u"松鼠桥接丁";if(it.word==u"松鼠桥接丁")pushMask=it.mask;platformAttrs+=it.attrs.size();masks.insert(it.mask);
  if(it.word==u"松鼠桥接甲"||it.word==u"松鼠桥接乙")fixtures.push_back({key,it.input,it.word,it.mask});
 }return true;};
 if(!visit || !visit(snap.get(),cb))return 5;
 std::cout<<"keys="<<keys<<" words="<<words<<" platformAttrs="<<platformAttrs<<" masks=";for(int m:masks)std::cout<<m<<",";std::cout<<"\n";
 std::cout<<"containsPublicTestWord="<<containsTest<<"\n";
 std::cout<<"containsPublicMacTestWord="<<containsMacTest<<"\n";
 std::cout<<"containsPushFixture="<<containsPushTest<<" pushFixturePlatformMask="<<pushMask<<"\n";
 // Exercise only the two public fixtures. This tests THIS desktop binary's
 // platform fallback, not the uninspected iOS build or its candidate ranking.
 struct KeyArray {uint64_t count;std::array<uint16_t,64> values{};};
 struct WordArray {uint64_t count;std::array<char16_t,64> values{};};
 using Preferred=bool(*)(const void*,const KeyArray&,const std::string&,const WordArray&,void*);
 auto preferred=(Preferred)dlsym(h,"_ZNK11oime_engine6pinyin11UsrSideDict35FindPreferredPlatformWordByKeyValueERKNS_9KFixArrayItLm64EEERKNSt3__112basic_stringIcNS6_11char_traitsIcEENS6_9allocatorIcEEEERKNS2_IDsLm64EEERNS0_19UsrSideFeatureStatsE");
 auto setDevice=(void(*)(int))dlsym(h,"_ZN11oime_engine13SetDeviceTypeENS_10DeviceTypeE");
 auto getDevice=(int(*)())dlsym(h,"_ZN11oime_engine13GetDeviceTypeEv");
 if(!preferred||!setDevice||!getDevice)return 7;
 for(const auto&fixture:fixtures){
  if(fixture.key.size()>64||fixture.word.size()>64)return 8;
  KeyArray k{fixture.key.size(),{}};WordArray w{fixture.word.size(),{}};
  std::copy(fixture.key.begin(),fixture.key.end(),k.values.begin());
  std::copy(fixture.word.begin(),fixture.word.end(),w.values.begin());
  std::cout<<(fixture.word==u"松鼠桥接甲"?"phoneFixture":"macFixture")<<" platformMask="<<int(fixture.mask);
  for(int device:{1,2}){
   setDevice(device);if(getDevice()!=device)return 9;
   alignas(8) std::array<uint8_t,64> stats{};
   std::cout<<" preferredForDevice"<<device<<"="<<preferred(snap.get(),k,fixture.input,w,stats.data());
  }
  std::cout<<"\n";
 }
 if(argc==4){auto text=exp(snap.get());std::ofstream out(argv[3]);if(!out)return 6;out<<text;out.close();std::cout<<"exportBytes="<<text.size()<<"\n";}
}
