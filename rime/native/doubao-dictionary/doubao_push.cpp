// Production helper: push Rime custom phrases into Mac Doubao's learned usr.dat.
//
// Runs as a separate, non-hardened executable outside Squirrel.app so it can
// dlopen the vendor OimeEngine.framework. The engine is pinned by SHA-256 and
// the private ABI is only used on macOS arm64.
//
// Safety: preview never writes live data; apply writes only the selected
// usr.dat, its backup, and a short-lived staging file in the account directory.
// Side dictionaries, sync state, and account files are not touched.

#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <libproc.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <ctime>
#include <fcntl.h>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr const char *kEnginePath =
    "/Library/Input Methods/DoubaoIme.app/Contents/Frameworks/OimeEngine.framework/Versions/A/OimeEngine";
constexpr const char *kEngineSHA256 =
    "f0da51a994a8a78b2955a45f14ddabc1a308bfcd4462961393c8881eb0217f62";
constexpr const char *kHelperVersion = "1";
constexpr unsigned long long kMaxDictBytes = 64ull * 1024 * 1024;

enum ExitCode {
  kOk = 0,
  kUsage = 2,
  kEngine = 10,
  kAccount = 11,
  kLoad = 12,
  kSave = 13,
  kLiveChanged = 14,
  kReplace = 15,
  kProcessRunning = 16,
  kInput = 17,
  kSelftest = 20,
};

struct Failure {
  int code;
  std::string name;
  std::string message;
};

[[noreturn]] void fail(int code, const char *name, const std::string &message) {
  throw Failure{code, name, message};
}

std::string trim(const std::string &s) {
  size_t a = 0, b = s.size();
  while (a < b && (s[a] == ' ' || s[a] == '\t' || s[a] == '\r' || s[a] == '\n')) ++a;
  while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r' || s[b - 1] == '\n')) --b;
  return s.substr(a, b - a);
}

std::vector<std::string> split(const std::string &s, const std::string &seps) {
  std::vector<std::string> out;
  std::string current;
  for (char c : s) {
    if (seps.find(c) != std::string::npos) {
      if (!current.empty()) { out.push_back(current); current.clear(); }
    } else {
      current.push_back(c);
    }
  }
  if (!current.empty()) out.push_back(current);
  return out;
}

std::string join(const std::vector<std::string> &parts, const std::string &sep) {
  std::string out;
  for (size_t i = 0; i < parts.size(); ++i) {
    if (i) out += sep;
    out += parts[i];
  }
  return out;
}

std::string homeDir() {
  const char *home = std::getenv("HOME");
  if (home && *home) return home;
  fail(kAccount, "home_missing", "HOME is not set");
}

fs::path doubaoAccountsDir() {
  return fs::path(homeDir()) / "Library/Application Support/DoubaoIme/EngineUserDictAccounts";
}

fs::path pushDir() {
  return fs::path(homeDir()) / "Library/Application Support/Squirrel/DoubaoPush";
}

void ensureDir(const fs::path &path, mode_t mode) {
  std::error_code ec;
  fs::create_directories(path, ec);
  if (ec) fail(kAccount, "mkdir_failed", "cannot create private directory");
  if (::chmod(path.c_str(), mode) != 0) fail(kAccount, "chmod_failed", "cannot secure private directory");
}

std::string readFile(const fs::path &path, size_t limit = kMaxDictBytes) {
  int fd = ::open(path.c_str(), O_RDONLY | O_NOFOLLOW);
  if (fd < 0) fail(kLoad, "open_failed", "cannot open file");
  struct stat st{};
  if (::fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0 ||
      static_cast<unsigned long long>(st.st_size) > limit) {
    ::close(fd);
    fail(kLoad, "invalid_file", "file is not a supported regular file");
  }
  std::string data;
  data.resize(static_cast<size_t>(st.st_size));
  size_t offset = 0;
  while (offset < data.size()) {
    ssize_t n = ::read(fd, data.data() + offset, data.size() - offset);
    if (n <= 0) { ::close(fd); fail(kLoad, "read_failed", "cannot read file"); }
    offset += static_cast<size_t>(n);
  }
  ::close(fd);
  return data;
}

std::string readStable(const fs::path &path) {
  for (int attempt = 0; attempt < 4; ++attempt) {
    std::string first = readFile(path);
    ::usleep(60000);
    std::string second = readFile(path);
    if (first == second) return first;
  }
  fail(kLoad, "changing", "dictionary is changing; retry after input stops");
}

std::string sha256Hex(const std::string &data) {
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.data(), static_cast<CC_LONG>(data.size()), digest);
  static const char *hex = "0123456789abcdef";
  std::string out;
  out.reserve(CC_SHA256_DIGEST_LENGTH * 2);
  for (unsigned char c : digest) {
    out.push_back(hex[c >> 4]);
    out.push_back(hex[c & 15]);
  }
  return out;
}

std::string sha256File(const fs::path &path) {
  int fd = ::open(path.c_str(), O_RDONLY | O_NOFOLLOW);
  if (fd < 0) fail(kEngine, "engine_missing", "Doubao engine is not installed");
  CC_SHA256_CTX ctx;
  CC_SHA256_Init(&ctx);
  std::array<unsigned char, 64 * 1024> buffer{};
  while (true) {
    ssize_t n = ::read(fd, buffer.data(), buffer.size());
    if (n < 0) { ::close(fd); fail(kEngine, "engine_read_failed", "cannot read Doubao engine"); }
    if (n == 0) break;
    CC_SHA256_Update(&ctx, buffer.data(), static_cast<CC_LONG>(n));
  }
  ::close(fd);
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(digest, &ctx);
  static const char *hex = "0123456789abcdef";
  std::string out;
  for (unsigned char c : digest) {
    out.push_back(hex[c >> 4]);
    out.push_back(hex[c & 15]);
  }
  return out;
}

void writeExclusive(const fs::path &path, const std::string &data, mode_t mode) {
  int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode);
  if (fd < 0) fail(kReplace, "create_failed", "cannot create output file");
  size_t offset = 0;
  while (offset < data.size()) {
    ssize_t n = ::write(fd, data.data() + offset, data.size() - offset);
    if (n <= 0) { ::close(fd); ::unlink(path.c_str()); fail(kReplace, "write_failed", "cannot write output file"); }
    offset += static_cast<size_t>(n);
  }
  if (::fsync(fd) != 0) { ::close(fd); ::unlink(path.c_str()); fail(kReplace, "fsync_failed", "cannot flush output file"); }
  if (::close(fd) != 0) fail(kReplace, "close_failed", "cannot close output file");
}

void fsyncDir(const fs::path &path) {
  int fd = ::open(path.c_str(), O_RDONLY | O_DIRECTORY);
  if (fd >= 0) { ::fsync(fd); ::close(fd); }
}

std::string localTimestamp() {
  std::time_t now = std::time(nullptr);
  std::tm tm{};
  localtime_r(&now, &tm);
  char buffer[32];
  std::strftime(buffer, sizeof(buffer), "%Y%m%d-%H%M%S", &tm);
  return buffer;
}

std::string cfToUtf8(CFStringRef string) {
  if (!string) return {};
  CFIndex length = CFStringGetLength(string);
  CFIndex max = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
  std::string out(static_cast<size_t>(max), '\0');
  if (!CFStringGetCString(string, out.data(), max, kCFStringEncodingUTF8)) return {};
  out.resize(std::strlen(out.c_str()));
  return out;
}

void replaceAll(std::string &value, const std::string &from, const std::string &to) {
  size_t pos = 0;
  while ((pos = value.find(from, pos)) != std::string::npos) {
    value.replace(pos, from.size(), to);
    pos += to.size();
  }
}

// Convert the Han parts of a word to pinyin syllables with CoreFoundation.
std::vector<std::string> systemSyllables(const std::string &word) {
  CFStringRef source = CFStringCreateWithCString(kCFAllocatorDefault, word.c_str(), kCFStringEncodingUTF8);
  if (!source) return {};
  CFMutableStringRef latin = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, source);
  CFRelease(source);
  if (!latin) return {};
  CFStringTransform(latin, nullptr, kCFStringTransformMandarinLatin, false);
  std::string text = cfToUtf8(latin);
  CFRelease(latin);
  if (text.empty()) return {};

  // Replace ü (and tone-marked variants) with v before stripping diacritics.
  replaceAll(text, "\xC3\xBC", "v");  // ü
  replaceAll(text, "\xC3\x9C", "v");  // Ü
  replaceAll(text, "\xC7\x96", "v");  // ǖ
  replaceAll(text, "\xC7\x98", "v");  // ǘ
  replaceAll(text, "\xC7\x9A", "v");  // ǚ
  replaceAll(text, "\xC7\x9C", "v");  // ǜ
  replaceAll(text, "u:", "v");
  replaceAll(text, "U:", "v");

  CFStringRef replaced = CFStringCreateWithCString(kCFAllocatorDefault, text.c_str(), kCFStringEncodingUTF8);
  if (!replaced) return {};
  CFMutableStringRef stripped = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, replaced);
  CFRelease(replaced);
  if (!stripped) return {};
  CFStringTransform(stripped, nullptr, kCFStringTransformStripDiacritics, false);
  std::string ascii = cfToUtf8(stripped);
  CFRelease(stripped);
  if (ascii.empty()) return {};

  std::vector<std::string> tokens = split(ascii, " '\t\r\n");
  std::vector<std::string> out;
  for (std::string token : tokens) {
    std::transform(token.begin(), token.end(), token.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    replaceAll(token, "u:", "v");
    for (char c : token) {
      if (!(c >= 'a' && c <= 'z')) return {};
    }
    if (!token.empty()) out.push_back(token);
  }
  return out;
}

struct Choice {
  bool valid = false;
  std::vector<std::string> syllables;
  std::string input;
  std::string source;
};

struct Engine {
  void *handle = nullptr;
  void *vtable = nullptr;
  using Load = bool (*)(void *, const std::string &, bool, void *);
  using Add = bool (*)(void *, const std::vector<uint16_t> &, const std::string &,
                       const std::u16string &, int);
  using Count = unsigned (*)(const void *);
  using Save = int (*)(void *, bool, void *);
  using Export = std::string (*)(const void *);
  using ToSyllable = bool (*)(const char *, uint16_t, uint16_t &);
  using SetDevice = void (*)(int);
  using Control = std::string (*)(const void *, const void *, unsigned, unsigned &);
  Load load = nullptr;
  Add add = nullptr;
  Count count = nullptr;
  Save save = nullptr;
  Export exportText = nullptr;
  ToSyllable toSyllable = nullptr;
  SetDevice setDevice = nullptr;
  Control control = nullptr;

  void open() {
    if (sha256File(kEnginePath) != kEngineSHA256) {
      fail(kEngine, "engine_mismatch", "Doubao engine version changed; rebuild doubao_push");
    }
    handle = ::dlopen(kEnginePath, RTLD_NOW | RTLD_LOCAL);
    if (!handle) fail(kEngine, "engine_load_failed", "cannot load Doubao engine");
    auto sym = [&](const char *name) -> void * {
      void *p = ::dlsym(handle, name);
      if (!p) fail(kEngine, "engine_symbol_missing", "Doubao engine ABI changed");
      return p;
    };
    load = reinterpret_cast<Load>(sym("_ZN11oime_engine6pinyin7UsrDict4LoadERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEEbPNS2_6vectorINS_8FdErrMsgENS6_ISC_EEEE"));
    add = reinterpret_cast<Add>(sym("_ZN11oime_engine6pinyin7UsrDict3AddERKNSt3__16vectorItNS2_9allocatorItEEEERKNS2_12basic_stringIcNS2_11char_traitsIcEENS4_IcEEEERKNS9_IDsNSA_IDsEENS4_IDsEEEENS_16WordInfoFlagTypeE"));
    count = reinterpret_cast<Count>(sym("_ZNK11oime_engine11UsrDictBase8GetCountEv"));
    save = reinterpret_cast<Save>(sym("_ZN11oime_engine11UsrDictBase4SaveEbPNS_12EventTrackerE"));
    exportText = reinterpret_cast<Export>(sym("_ZNK11oime_engine6pinyin7UsrDict18ExportDictToStringEv"));
    toSyllable = reinterpret_cast<ToSyllable>(sym("_ZN11oime_engine18PinyinToSyllableIdEPKctRt"));
    setDevice = reinterpret_cast<SetDevice>(sym("_ZN11oime_engine13SetDeviceTypeENS_10DeviceTypeE"));
    control = reinterpret_cast<Control>(sym("_ZN11oime_engine4sync28GenUploadTaskControlPbStreamEPKNS_6pinyin7UsrDictEPKNS1_11UsrSideDictEjRj"));
    void *table = sym("_ZTVN11oime_engine6pinyin7UsrDictE");
    vtable = static_cast<char *>(table) + 16;
  }

  void *makeDict() const {
    void *object = std::calloc(1, 4096);
    if (!object) fail(kLoad, "alloc_failed", "cannot allocate dictionary");
    *static_cast<void **>(object) = vtable;
    return object;
  }

  bool syllableId(const std::string &syllable, uint16_t &id) {
    id = 0;
    return toSyllable(syllable.c_str(), static_cast<uint16_t>(syllable.size()), id) && id != 0;
  }
};

struct Entry {
  size_t index = 0;
  std::string word;
  std::string code;
  std::string weight;
};

struct Row {
  Entry entry;
  Choice choice;
  std::string status;
  std::string detail;
};

std::vector<Entry> readEntries(std::istream &input, std::vector<Row> &invalidRows) {
  std::vector<Entry> entries;
  std::string line;
  size_t index = 0;
  while (std::getline(input, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.empty() || line[0] == '#') continue;
    std::vector<std::string> columns;
    size_t start = 0;
    while (start <= line.size()) {
      size_t tab = line.find('\t', start);
      if (tab == std::string::npos) { columns.push_back(line.substr(start)); break; }
      columns.push_back(line.substr(start, tab - start));
      start = tab + 1;
    }
    Entry entry;
    entry.index = index++;
    if (columns.size() >= 1) entry.word = trim(columns[0]);
    if (columns.size() >= 2) entry.code = trim(columns[1]);
    if (columns.size() >= 3) entry.weight = trim(columns[2]);
    if (columns.size() < 2 || entry.word.empty() || entry.code.empty()) {
      Row row; row.entry = entry; row.status = "skipped"; row.detail = "missing column";
      invalidRows.push_back(row);
      continue;
    }
    entries.push_back(entry);
  }
  return entries;
}

std::u16string toUtf16(const std::string &text) {
  CFStringRef string = CFStringCreateWithCString(kCFAllocatorDefault, text.c_str(), kCFStringEncodingUTF8);
  if (!string) return {};
  CFIndex length = CFStringGetLength(string);
  std::u16string out(static_cast<size_t>(length), 0);
  if (length > 0) CFStringGetCharacters(string, CFRangeMake(0, length), reinterpret_cast<UniChar *>(out.data()));
  CFRelease(string);
  return out;
}

bool validWord(const std::string &word, std::u16string &utf16) {
  if (word.empty()) return false;
  for (unsigned char c : word) {
    if (c < 0x20 || c == 0x7F) return false;
  }
  if (word.find('\t') != std::string::npos) return false;
  utf16 = toUtf16(word);
  if (utf16.empty() || utf16.size() > 64) return false;
  return true;
}

class Pinyin {
 public:
  explicit Pinyin(Engine &engine) : engine_(engine) {}

  Choice choose(const std::string &word, const std::string &rawCode) {
    Choice choice;
    std::string code = rawCode;
    std::transform(code.begin(), code.end(), code.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    std::vector<std::string> system = systemSyllables(word);
    bool systemValid = !system.empty() && validate(system);
    if (!systemValid) system.clear();
    std::string normalized = code;
    normalized.erase(std::remove_if(normalized.begin(), normalized.end(), [](char c) { return c == ' ' || c == '\'' || c == '\t'; }), normalized.end());
    if (normalized.empty()) return choice;
    if (normalized.size() > 64) return choice;

    bool explicitSeparators = code.find(' ') != std::string::npos || code.find('\'') != std::string::npos;
    if (explicitSeparators) {
      std::vector<std::string> explicitParts = split(code, " '\t");
      if (!explicitParts.empty() && validate(explicitParts) && join(explicitParts, "") == normalized) {
        choice.valid = true; choice.syllables = explicitParts; choice.input = normalized; choice.source = "explicit";
        return choice;
      }
    }

    if (systemValid && join(system, "") == normalized) {
      choice.valid = true; choice.syllables = system; choice.input = normalized; choice.source = "canonical";
      return choice;
    }

    DpResult dp = segment(normalized, 0);
    if (dp.valid) {
      choice.valid = true; choice.syllables = dp.split; choice.input = normalized;
      choice.source = dp.ways >= 2 ? "ambiguous" : "code";
      return choice;
    }

    if (systemValid) {
      choice.valid = true; choice.syllables = system; choice.input = join(system, ""); choice.source = "system";
      return choice;
    }
    return choice;
  }

  bool validate(const std::vector<std::string> &syllables) {
    if (syllables.empty() || syllables.size() > 64) return false;
    for (const std::string &syllable : syllables) {
      if (syllable.empty()) return false;
      if (!validSyllable(syllable)) return false;
    }
    return true;
  }

 private:
  struct DpResult {
    bool valid = false;
    int count = std::numeric_limits<int>::max();
    int ways = 0;
    std::vector<std::string> split;
  };

  Engine &engine_;
  std::unordered_map<std::string, bool> syllableCache_;
  std::map<std::pair<std::string, size_t>, DpResult> dpCache_;

  bool validSyllable(const std::string &syllable) {
    auto it = syllableCache_.find(syllable);
    if (it != syllableCache_.end()) return it->second;
    uint16_t id = 0;
    bool ok = engine_.syllableId(syllable, id);
    syllableCache_[syllable] = ok;
    return ok;
  }

  DpResult segment(const std::string &code, size_t pos) {
    if (pos == code.size()) return DpResult{true, 0, 1, {}};
    auto key = std::make_pair(code, pos);
    auto cached = dpCache_.find(key);
    if (cached != dpCache_.end()) return cached->second;
    DpResult best;
    size_t maxEnd = std::min(code.size(), pos + 6);
    for (size_t end = pos + 1; end <= maxEnd; ++end) {
      std::string syllable = code.substr(pos, end - pos);
      if (!validSyllable(syllable)) continue;
      DpResult rest = segment(code, end);
      if (!rest.valid) continue;
      int count = rest.count + 1;
      if (count < best.count) {
        best.valid = true;
        best.count = count;
        best.ways = rest.ways;
        best.split.clear();
        best.split.push_back(syllable);
        best.split.insert(best.split.end(), rest.split.begin(), rest.split.end());
      } else if (count == best.count) {
        best.ways = std::min(2, best.ways + rest.ways);
      }
    }
    dpCache_[key] = best;
    return best;
  }
};

struct Options {
  bool preview = false;
  bool apply = false;
  bool selftest = false;
  bool version = false;
  std::string inputPath;
  std::string accountDir;
  std::string backupDir;
};

std::string discoverAccount(const std::string &overrideDir) {
  fs::path account;
  if (!overrideDir.empty()) {
    account = fs::path(overrideDir);
  } else {
    fs::path root = doubaoAccountsDir();
    std::error_code ec;
    if (!fs::is_directory(root, ec)) fail(kAccount, "account_missing", "Doubao account dictionary not found");
    std::vector<fs::path> matches;
    for (const auto &item : fs::directory_iterator(root, ec)) {
      if (ec) break;
      std::error_code typeError;
      if (!item.is_directory(typeError) || typeError) continue;
      if (item.is_symlink(typeError) || typeError) continue;
      fs::path candidate = item.path() / "usr.dat";
      std::error_code fileError;
      if (fs::is_regular_file(candidate, fileError) && !fileError) matches.push_back(item.path());
    }
    if (matches.size() != 1) {
      fail(kAccount, "account_ambiguous", "expected exactly one Doubao account dictionary");
    }
    account = matches.front();
  }
  fs::path file = account / "usr.dat";
  std::error_code error;
  if (fs::is_symlink(file, error) || error) fail(kAccount, "account_symlink", "refusing a dictionary symlink");
  if (!fs::is_regular_file(file, error) || error) fail(kAccount, "dictionary_missing", "Doubao learned dictionary not found");
  return account.string();
}

bool processByName(const std::string &name) {
  int count = ::proc_listallpids(nullptr, 0);
  if (count <= 0) return false;
  std::vector<pid_t> pids(static_cast<size_t>(count) + 32);
  count = ::proc_listallpids(pids.data(), static_cast<int>(pids.size() * sizeof(pid_t)));
  if (count <= 0) return false;
  for (int i = 0; i < count; ++i) {
    pid_t pid = pids[static_cast<size_t>(i)];
    if (pid <= 0) continue;
    char path[PROC_PIDPATHINFO_MAXSIZE] = {};
    if (::proc_pidpath(pid, path, sizeof(path)) <= 0) continue;
    std::string value(path);
    if (value.size() >= name.size() && value.compare(value.size() - name.size(), name.size(), name) == 0) return true;
  }
  return false;
}

std::string makeTempDir() {
  fs::path root = pushDir();
  ensureDir(root, 0700);
  std::string pattern = (root / "tmp-XXXXXX").string();
  std::vector<char> buffer(pattern.begin(), pattern.end());
  buffer.push_back('\0');
  char *created = ::mkdtemp(buffer.data());
  if (!created) fail(kAccount, "temp_failed", "cannot create private temporary directory");
  return std::string(created);
}

struct Scope {
  std::vector<fs::path> files;
  std::vector<fs::path> dirs;
  ~Scope() {
    std::error_code error;
    for (const auto &file : files) fs::remove(file, error);
    for (auto it = dirs.rbegin(); it != dirs.rend(); ++it) fs::remove_all(*it, error);
  }
};

struct ApplyResult {
  size_t added = 0;
  size_t exists = 0;
  size_t skipped = 0;
  size_t failed = 0;
  std::string backup;
};

struct Session {
  Engine &engine;
  Pinyin pinyin;
  std::string accountDir;
  fs::path liveFile;
  std::string snapshot;
  std::string originalHash;
  unsigned originalCount = 0;
  void *dict = nullptr;
  std::string stagingDir;
  Scope scope;

  Session(Engine &e, const std::string &account)
      : engine(e), pinyin(e), accountDir(account),
        liveFile(fs::path(account) / "usr.dat") {
    originalHash = sha256File(liveFile);
    snapshot = readStable(liveFile);
    if (sha256Hex(snapshot) != originalHash) fail(kLiveChanged, "live_changed", "dictionary changed while reading");
    stagingDir = makeTempDir();
    scope.dirs.push_back(fs::path(stagingDir));
    fs::path stagingFile = fs::path(stagingDir) / "usr.dat";
    writeExclusive(stagingFile, snapshot, 0600);
    dict = engine.makeDict();
    if (!engine.load(dict, stagingDir, false, nullptr)) fail(kLoad, "load_failed", "cannot load learned dictionary");
    originalCount = engine.count(dict);
  }

  Row evaluate(const Entry &entry) {
    Row row;
    row.entry = entry;
    std::u16string utf16;
    if (!validWord(entry.word, utf16)) {
      row.status = "skipped";
      row.detail = "word";
      return row;
    }
    if (entry.code.empty()) {
      row.status = "skipped";
      row.detail = "code";
      return row;
    }
    Choice choice = pinyin.choose(entry.word, entry.code);
    row.choice = choice;
    if (!choice.valid || choice.syllables.size() > 64 || choice.input.size() > 64) {
      row.status = "invalid_pinyin";
      return row;
    }
    std::vector<uint16_t> ids;
    ids.reserve(choice.syllables.size());
    for (const std::string &syllable : choice.syllables) {
      uint16_t id = 0;
      if (!engine.syllableId(syllable, id)) {
        row.status = "invalid_pinyin";
        return row;
      }
      ids.push_back(id);
    }
    unsigned before = engine.count(dict);
    bool ok = engine.add(dict, ids, choice.input, utf16, 0);
    unsigned after = engine.count(dict);
    if (!ok) {
      row.status = "error";
      row.detail = "add";
    } else if (after > before) {
      row.status = "ok";
    } else {
      row.status = "exists";
    }
    return row;
  }

  void printRow(const Row &row) const {
    std::cout << "P\t" << row.entry.index << '\t' << row.entry.word << '\t'
              << row.choice.input << '\t' << join(row.choice.syllables, " ") << '\t'
              << (row.choice.source.empty() ? "-" : row.choice.source) << '\t'
              << row.status << '\n';
  }

  ApplyResult apply(const std::vector<Entry> &entries, const std::string &backupOverride) {
    ApplyResult result;
    std::set<std::string> seen;
    std::vector<std::pair<Entry, Choice>> addedWords;
    for (const Entry &entry : entries) {
      std::string key = entry.word + "\t" + entry.code;
      if (!seen.insert(key).second) { ++result.skipped; continue; }
      Row row = evaluate(entry);
      if (row.status == "ok") {
        ++result.added;
        addedWords.emplace_back(entry, row.choice);
      } else if (row.status == "exists") {
        ++result.exists;
      } else if (row.status == "skipped") {
        ++result.skipped;
      } else {
        ++result.failed;
      }
    }
    if (result.added == 0) return result;

    if (engine.save(dict, true, nullptr) != 0) fail(kSave, "save_failed", "cannot save learned dictionary");
    fs::path staged = fs::path(stagingDir) / "usr.dat";
    std::string saved = readFile(staged);
    if (saved.empty()) fail(kSave, "save_empty", "saved dictionary is empty");

    void *reloaded = engine.makeDict();
    if (!engine.load(reloaded, stagingDir, false, nullptr)) fail(kSave, "reload_failed", "cannot reload saved dictionary");
    unsigned newCount = engine.count(reloaded);
    if (newCount < originalCount) fail(kSave, "pruned", "saved dictionary lost existing words");
    std::string exported = engine.exportText(reloaded);
    auto exportedWord = [&](const Entry &entry, const Choice &choice) {
      std::string prefix = entry.word + "(" + join(choice.syllables, "|") + ")";
      size_t at = 0;
      while ((at = exported.find(prefix, at)) != std::string::npos) {
        size_t end = exported.find('\n', at);
        if (end == std::string::npos) end = exported.size();
        std::string line = exported.substr(at, end - at);
        size_t close = line.find(')', prefix.size() - 1);
        size_t start = close == std::string::npos ? std::string::npos : close + 1;
        while (start != std::string::npos && start < line.size() && line[start] == ' ') ++start;
        if (start != std::string::npos && line.compare(start, choice.input.size(), choice.input) == 0) return true;
        at += prefix.size();
      }
      return false;
    };
    for (const auto &pair : addedWords) {
      if (!exportedWord(pair.first, pair.second)) {
        fail(kSave, "verify_failed", "saved dictionary is missing an added word");
      }
    }

    fs::path backupDir = backupOverride.empty()
                              ? pushDir() / "backups"
                              : fs::path(backupOverride);
    ensureDir(backupDir, 0700);
    fs::path backup = backupDir / ("usr.dat.bak-" + localTimestamp() + "-" + std::to_string(::getpid()));
    writeExclusive(backup, snapshot, 0600);
    if (sha256File(backup) != originalHash) fail(kReplace, "backup_mismatch", "backup verification failed");
    result.backup = backup.string();

    std::string current = readStable(liveFile);
    if (sha256Hex(current) != originalHash) fail(kLiveChanged, "live_changed", "dictionary changed before replace");

    fs::path newFile = fs::path(accountDir) / (".usr.dat." + std::to_string(::getpid()) + ".tmp");
    writeExclusive(newFile, saved, 0600);
    if (::rename(newFile.c_str(), liveFile.c_str()) != 0) {
      ::unlink(newFile.c_str());
      fail(kReplace, "rename_failed", "cannot replace learned dictionary");
    }
    fsyncDir(fs::path(accountDir));
    return result;
  }
};

void printFailure(const Failure &failure) {
  std::cerr << "E\t" << failure.name << '\t' << failure.message << '\n';
}

void runOptions(const Options &options) {
  if (options.version) {
    bool engineOk = false;
    try {
      engineOk = sha256File(kEnginePath) == kEngineSHA256;
    } catch (const Failure &) {
      engineOk = false;
    }
    std::cout << "V\tversion=" << kHelperVersion << "\tengine_sha256=" << kEngineSHA256
              << "\tengine_ok=" << (engineOk ? 1 : 0) << '\n';
    if (!engineOk) throw Failure{kEngine, "engine_mismatch", "Doubao engine version changed; rebuild doubao_push"};
    return;
  }

  Engine engine;
  engine.open();

  if (options.selftest) {
    // Selftest uses a synthetic account under the push directory and never
    // reads or writes the live Doubao account.
    std::string temp = makeTempDir();
    Scope scope;
    scope.dirs.push_back(fs::path(temp));
    fs::path account = fs::path(temp) / "account";
    ensureDir(account, 0700);
    void *seed = engine.makeDict();
    if (!engine.load(seed, account.string(), true, nullptr)) fail(kSelftest, "selftest_load", "cannot create synthetic dictionary");
    if (engine.save(seed, true, nullptr) != 0) fail(kSelftest, "selftest_save", "cannot save synthetic dictionary");
    Options test = options;
    test.preview = false;
    test.apply = true;
    test.selftest = false;
    test.accountDir = account.string();
    test.backupDir = (fs::path(temp) / "backups").string();
    std::istringstream input(
        "松鼠桥接丁\tsongshuqiaojieding\n"
        "西安\txian\n"
        "测试A\tceshia\n"
        "女\tnv\n"
        "名称\tceshimingcheng\n"
        "长干\tchangan\n"
        "松鼠\tsongshuqiaojieding\n"
        "重复\tceshi\n"
        "重复\tceshi\n"
        "yangyu445\tyangyu\n"
        "yangyu445@jd.com\tyangyu\n"
        "test@example.com\ttest\n"
        "𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀𠀀\ttest\n");
    std::vector<Row> invalid;
    std::vector<Entry> entries = readEntries(input, invalid);
    Session preview(engine, account.string());
    for (const Entry &entry : entries) preview.printRow(preview.evaluate(entry));
    Session session(engine, account.string());
    ApplyResult first = session.apply(entries, test.backupDir);
    if (first.added < 10) fail(kSelftest, "selftest_added", "selftest did not add expected words");
    if (first.backup.empty()) fail(kSelftest, "selftest_backup", "selftest did not create a backup");
    if (engine.count(session.dict) == 0) fail(kSelftest, "selftest_count", "selftest dictionary is empty");
    engine.setDevice(2);
    unsigned checkpoint = 0;
    std::string payload = engine.control(session.dict, nullptr, 0, checkpoint);
    if (payload.empty() || payload.find("songshuqiaojieding") == std::string::npos) {
      fail(kSelftest, "selftest_upload", "upload control is empty or lacks the test word");
    }
    Session again(engine, account.string());
    ApplyResult second = again.apply(entries, test.backupDir);
    if (second.added != 0) fail(kSelftest, "selftest_idempotent", "duplicate apply added words");
    std::cout << "S\tselftest=ok\tfirst_added=" << first.added << "\tsecond_added=" << second.added << '\n';
    return;
  }

  std::string account = discoverAccount(options.accountDir);
  if (options.apply && processByName("DoubaoIme")) {
    fail(kProcessRunning, "doubao_running", "quit Doubao before applying the dictionary");
  }

  std::ifstream file;
  std::istream *input = &std::cin;
  if (!options.inputPath.empty()) {
    file.open(options.inputPath);
    if (!file) fail(kInput, "input_open", "cannot open input file");
    input = &file;
  }
  std::vector<Row> invalid;
  std::vector<Entry> entries = readEntries(*input, invalid);

  if (options.preview) {
    Session session(engine, account);
    for (const Row &row : invalid) session.printRow(row);
    for (const Entry &entry : entries) session.printRow(session.evaluate(entry));
    return;
  }

  Session session(engine, account);
  ApplyResult result = session.apply(entries, options.backupDir);
  std::cout << "A\tadded=" << result.added << "\texists=" << result.exists
            << "\tskipped=" << result.skipped << "\tfailed=" << result.failed
            << "\tbackup=" << result.backup << '\n';
}

Options parseOptions(int argc, char **argv) {
  Options options;
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    auto value = [&](const char *name) -> std::string {
      if (i + 1 >= argc) fail(kUsage, "usage", std::string("missing value for ") + name);
      return argv[++i];
    };
    if (arg == "--preview") options.preview = true;
    else if (arg == "--apply") options.apply = true;
    else if (arg == "--selftest") options.selftest = true;
    else if (arg == "--version") options.version = true;
    else if (arg == "--input") options.inputPath = value("--input");
    else if (arg == "--account-dir") options.accountDir = value("--account-dir");
    else if (arg == "--backup-dir") options.backupDir = value("--backup-dir");
    else fail(kUsage, "usage", "unknown argument");
  }
  if (!options.preview && !options.apply && !options.selftest && !options.version) {
    fail(kUsage, "usage", "use --preview, --apply, --selftest, or --version");
  }
  if ((options.preview ? 1 : 0) + (options.apply ? 1 : 0) + (options.selftest ? 1 : 0) + (options.version ? 1 : 0) > 1) {
    fail(kUsage, "usage", "choose one operation");
  }
  return options;
}

}  // namespace

int main(int argc, char **argv) {
  ::signal(SIGPIPE, SIG_IGN);
  try {
    Options options = parseOptions(argc, argv);
    runOptions(options);
    return kOk;
  } catch (const Failure &failure) {
    printFailure(failure);
    return failure.code;
  } catch (const std::exception &error) {
    std::cerr << "E\tinternal\t" << error.what() << '\n';
    return kUsage;
  }
}
