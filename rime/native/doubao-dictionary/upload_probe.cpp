// Research only: synthetic learned dictionary; never reads live data or sends network.
#include <dlfcn.h>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

template <class T> T sym(void *h, const char *n) {
  auto p = dlsym(h, n);
  if (!p) { std::cerr << "missing symbol " << n << "\n"; exit(2); }
  return reinterpret_cast<T>(p);
}

static std::string base64(const std::string &in) {
  static const char *t = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  unsigned val = 0; int bits = -6;
  for (unsigned char c : in) {
    val = (val << 8) + c; bits += 8;
    while (bits >= 0) { out.push_back(t[(val >> bits) & 63]); bits -= 6; }
  }
  if (bits > -6) out.push_back(t[((val << 8) >> (bits + 8)) & 63]);
  while (out.size() % 4) out.push_back('=');
  return out;
}

int main(int argc, char **argv) {
  if (argc < 3 || argc > 4) return 64;
  void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!h) { std::cerr << dlerror() << "\n"; return 2; }
  using Load = bool (*)(void *, const std::string &, bool, void *);
  using Add = bool (*)(void *, const std::vector<uint16_t> &, const std::string &,
                       const std::u16string &, int);
  using Save = int (*)(void *, bool, void *);
  using Control = std::string (*)(const void *, const void *, unsigned, unsigned &);
  auto load = sym<Load>(h, "_ZN11oime_engine6pinyin7UsrDict4LoadERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEEbPNS2_6vectorINS_8FdErrMsgENS6_ISC_EEEE");
  auto add = sym<Add>(h, "_ZN11oime_engine6pinyin7UsrDict3AddERKNSt3__16vectorItNS2_9allocatorItEEEERKNS2_12basic_stringIcNS2_11char_traitsIcEENS4_IcEEEERKNS9_IDsNSA_IDsEENS4_IDsEEEENS_16WordInfoFlagTypeE");
  auto save = sym<Save>(h, "_ZN11oime_engine11UsrDictBase4SaveEbPNS_12EventTrackerE");
  auto control = sym<Control>(h, "_ZN11oime_engine4sync28GenUploadTaskControlPbStreamEPKNS_6pinyin7UsrDictEPKNS1_11UsrSideDictEjRj");
  auto vtable = static_cast<char *>(sym<void *>(h, "_ZTVN11oime_engine6pinyin7UsrDictE")) + 16;
  auto toSyll = sym<bool (*)(const char *, uint16_t, uint16_t &)>(h, "_ZN11oime_engine18PinyinToSyllableIdEPKctRt");
  auto setDevice = sym<void (*)(int)>(h, "_ZN11oime_engine13SetDeviceTypeENS_10DeviceTypeE");
  auto count = sym<unsigned (*)(const void *)>(h, "_ZNK11oime_engine11UsrDictBase8GetCountEv");
  using Prep = int (*)(const std::string &, std::shared_ptr<const void> &, unsigned long long *, std::string *);
  auto prep = sym<Prep>(h, "_ZN11oime_engine6pinyin11UsrSideDict15PrepareSnapshotERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEERNS2_10shared_ptrIKS1_EEPyPS8_");
  std::shared_ptr<const void> side;
  if (argc == 4) {
    unsigned long long generation = 0;
    std::string path;
    int status = prep(std::string(argv[3]), side, &generation, &path);
    std::cerr << "side status=" << status << " loaded=" << bool(side) << "\n";
    if (status || !side) return 7;
  }

  void *dict = calloc(1, 4096);
  *static_cast<void **>(dict) = vtable;
  if (!load(dict, std::string(argv[2]), true, nullptr)) return 3;
  std::cerr << "load count=" << count(dict) << "\n";

  std::string py = "rimesyncprobe";
  std::u16string asciiWord = u"RimeSyncProbe";
  std::vector<uint16_t> asciiSyll;
  for (char c : py) asciiSyll.push_back(10 + c - 'a');
  if (!add(dict, asciiSyll, py, asciiWord, 0)) return 5;
  std::cerr << "after ascii count=" << count(dict) << " save=" << save(dict, true, nullptr) << "\n";

  std::vector<uint16_t> syll;
  for (const std::string s : {"song", "shu", "qiao", "jie", "bing"}) {
    uint16_t id = 0;
    if (!toSyll(s.data(), s.size(), id) || !id) return 4;
    syll.push_back(id);
  }
  if (!add(dict, syll, "songshuqiaojiebing", u"松鼠桥接丙", 0)) return 5;
  int saved = save(dict, true, nullptr);
  std::cerr << "after chinese count=" << count(dict) << " save=" << saved << "\n";
  if (saved != 0) return 6;

  for (int device : {1, 2}) {
    setDevice(device);
    unsigned checkpoint = 0;
    std::string payload = control(dict, side.get(), 0, checkpoint);
    std::cout << "device=" << device << " bytes=" << payload.size()
              << " checkpoint=" << checkpoint << "\n";
    if (payload.size() <= 4096) std::cout << base64(payload) << "\n";
  }
  return 0;
}
