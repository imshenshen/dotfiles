#pragma once

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <tuple>
#include <vector>

namespace cloud_pinyin {
using Clock = std::chrono::steady_clock;
using Words = std::vector<std::string>;
// Private UI metadata: provider bitmask between U+E000 / U+E001, then the
// original native comment. Squirrel renders one badge and preserves that comment.
inline std::string CloudComment(unsigned providers, const std::string& native_comment = {}) {
  return "\xEE\x80\x80" + std::to_string(providers) + "\xEE\x80\x81" + native_comment;
}

// Cache values never contain a Rime Candidate or a composition position.
struct Key {
  std::string provider, pinyin;
  int limit = 5;
  int adapter_version = 1;
  bool operator<(const Key& rhs) const {
    return std::tie(provider, pinyin, limit, adapter_version) <
           std::tie(rhs.provider, rhs.pinyin, rhs.limit, rhs.adapter_version);
  }
};

class Cache {
 public:
  explicit Cache(size_t capacity = 256) : capacity_(capacity) {}
  void SetCapacity(size_t capacity) {
    capacity_ = std::max(size_t(1), capacity);
    Trim();
  }
  const Words* Get(const Key& key, Clock::time_point now = Clock::now()) {
    auto found = entries_.find(key);
    if (found == entries_.end()) return nullptr;
    if (now >= found->second.expires) {
      entries_.erase(found);
      return nullptr;
    }
    found->second.used = ++sequence_;
    return &found->second.words;
  }
  void Put(const Key& key, Words words, std::chrono::milliseconds ttl,
           Clock::time_point now = Clock::now()) {
    entries_[key] = {std::move(words), now + ttl, ++sequence_};
    Trim();
  }
  void Clear() { entries_.clear(); }
  size_t size() const { return entries_.size(); }

 private:
  struct Entry {
    Words words;
    Clock::time_point expires;
    uint64_t used;
  };
  void Trim() {
    while (entries_.size() > capacity_) {
      auto oldest = std::min_element(entries_.begin(), entries_.end(),
          [](const auto& a, const auto& b) { return a.second.used < b.second.used; });
      entries_.erase(oldest);
    }
  }
  size_t capacity_;
  uint64_t sequence_ = 0;
  std::map<Key, Entry> entries_;
};

struct Pick {
  // -2: custom dictionary; -1: local; 0...: configured provider index.
  int source;
  size_t index;
  std::string text;
};

inline std::vector<Pick> Interleave(const Words& custom, const Words& local,
                                   const std::vector<Words>& providers) {
  std::vector<Pick> result;
  std::set<std::string> seen;
  auto append = [&](int source, size_t index, const Words& words) {
    if (index < words.size() && !words[index].empty() && seen.insert(words[index]).second)
      result.push_back({source, index, words[index]});
  };
  for (size_t i = 0; i < custom.size(); ++i) append(-2, i, custom);
  size_t count = local.size();
  for (const auto& words : providers) count = std::max(count, words.size());
  for (size_t i = 0; i < count; ++i) {
    append(-1, i, local);
    for (size_t p = 0; p < providers.size(); ++p) append(int(p), i, providers[p]);
  }
  return result;
}

inline bool ValidPinyin(const std::string& code) {
  if (code.empty() || code.size() > 128) return false;
  return std::all_of(code.begin(), code.end(), [](char c) {
    return (c >= 'a' && c <= 'z') || c == '\'';
  });
}

// The third Sogou field is a list of uint16 syllable end offsets. Only accept
// candidates whose last offset consumes the entire request, not a prefix.
struct SogouWord {
  std::vector<uint8_t> utf16;
  size_t consumed;
};
inline std::vector<SogouWord> DecodeSogou(const uint8_t* data, size_t length) {
  if (length < 20 || size_t(data[0]) + 2 != length) return {};
  size_t pos = 18;
  auto u16 = [&](uint16_t& value) {
    if (pos + 2 > length) return false;
    value = uint16_t(data[pos]) | (uint16_t(data[pos + 1]) << 8);
    pos += 2;
    return true;
  };
  uint16_t count;
  if (!u16(count) || count > 32) return {};
  std::vector<SogouWord> words;
  for (size_t i = 0; i < count; ++i) {
    uint16_t size;
    if (!u16(size) || size % 2 || pos + size > length) return {};
    SogouWord word{{data + pos, data + pos + size}, 0};
    pos += size;
    if (!u16(size) || pos + size > length) return {};
    pos += size; // opaque syllable identifiers
    if (!u16(size) || size == 0 || size % 2 || pos + size + 1 > length) return {};
    size_t previous = 0;
    for (size_t j = 0; j < size; j += 2) {
      size_t offset = data[pos + j] | (size_t(data[pos + j + 1]) << 8);
      if (offset <= previous) return {};
      previous = offset;
    }
    word.consumed = previous;
    pos += size + 1; // trailing packet marker
    words.push_back(std::move(word));
  }
  return pos == length ? words : std::vector<SogouWord>{};
}
} // namespace cloud_pinyin
