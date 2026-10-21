// Research only: read a private copy. Never prints phrase text.
#include <dlfcn.h>
#include <cstdlib>
#include <iostream>
#include <string>

int main(int argc, char **argv) {
  if (argc != 3) return 64;
  void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!h) { std::cerr << dlerror() << "\n"; return 2; }
  using Load = bool (*)(void *, const std::string &, bool, void *);
  using Count = unsigned (*)(const void *);
  auto load = reinterpret_cast<Load>(dlsym(h,
      "_ZN11oime_engine6pinyin16CommonPhraseDict4LoadERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEEbPNS2_6vectorINS_8FdErrMsgENS6_ISC_EEEE"));
  auto count = reinterpret_cast<Count>(dlsym(h, "_ZNK11oime_engine14CustomDictBase8GetCountEv"));
  auto prime = reinterpret_cast<Count>(dlsym(h, "_ZNK11oime_engine6pinyin16CommonPhraseDict13GetPrimeCountEv"));
  auto table = dlsym(h, "_ZTVN11oime_engine6pinyin16CommonPhraseDictE");
  if (!load || !count || !prime || !table) return 3;
  void *object = calloc(1, 4096);
  if (!object) return 4;
  *static_cast<void **>(object) = static_cast<char *>(table) + 16;
  if (!load(object, std::string(argv[2]), false, nullptr)) return 5;
  std::cout << "commonPhraseRecords=" << count(object)
            << " prime=" << prime(object) << "\n";
  return 0;
}
