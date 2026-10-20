// Research only: read a private copy. The wrapper pins the engine SHA and
// denies network access, live-data reads and writes outside the temporary work.
#include <dlfcn.h>
#include <cstdlib>
#include <iostream>
#include <string>

int main(int argc, char **argv) {
  if (argc != 3) return 64;
  void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!handle) return 2;
  using Load = bool (*)(void *, const std::string &, bool, void *);
  using Export = std::string (*)(const void *);
  using Count = unsigned (*)(const void *);
  auto load = reinterpret_cast<Load>(dlsym(handle,
      "_ZN11oime_engine6pinyin7UsrDict4LoadERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEEbPNS2_6vectorINS_8FdErrMsgENS6_ISC_EEEE"));
  auto exportWords = reinterpret_cast<Export>(dlsym(handle,
      "_ZNK11oime_engine6pinyin7UsrDict18ExportDictToStringEv"));
  auto count = reinterpret_cast<Count>(dlsym(handle,
      "_ZNK11oime_engine11UsrDictBase8GetCountEv"));
  auto table = dlsym(handle, "_ZTVN11oime_engine6pinyin7UsrDictE");
  if (!load || !exportWords || !count || !table) return 3;
  void *object = calloc(1, 4096);
  if (!object) return 4;
  *static_cast<void **>(object) = static_cast<char *>(table) + 16;
  if (!load(object, std::string(argv[2]), false, nullptr)) return 5;
  const auto text = exportWords(object);
  std::cout << "localLearnedRecords=" << count(object) << "\n"
            << "localContainsPhoneFixture=" << (text.find("松鼠桥接甲") != std::string::npos) << "\n"
            << "localContainsMacFixture=" << (text.find("松鼠桥接乙") != std::string::npos) << "\n";
}
