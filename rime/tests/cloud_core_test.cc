#include "../native/cloud_pinyin/core.h"
#include <cassert>
#include <iostream>

using namespace cloud_pinyin;
int main() {
  auto merged = Interleave({"自定义", "本地一"}, {"本地一", "本地二", "本地三"},
                           {{"搜狗一", "搜狗二"}, {"谷歌一", "本地二", "谷歌三"}});
  Words result;
  for (auto& pick : merged) result.push_back(pick.text);
  assert((result == Words{"自定义", "本地一", "搜狗一", "谷歌一", "本地二", "搜狗二", "本地三", "谷歌三"}));
  assert(merged[1].source == -2); // Custom duplicates keep custom provenance.

  Cache cache(2);
  auto now = Clock::time_point{};
  Key a{"sogou", "nihao"}, b{"google", "nihao"}, c{"sogou", "nihaoshijie"};
  cache.Put(a, {"你好"}, std::chrono::seconds(300), now);
  cache.Put(b, {"你好"}, std::chrono::seconds(300), now);
  assert(cache.Get(a, now + std::chrono::seconds(299)));
  assert(!cache.Get(a, now + std::chrono::seconds(300))); // Reads don't extend TTL.
  assert(cache.Get(b, now));
  cache.Put(a, {"你好"}, std::chrono::seconds(300), now);
  cache.Put(c, {"你好世界"}, std::chrono::seconds(300), now);
  assert(!cache.Get(b, now)); // Least recently used entry was evicted.
  assert(cache.Get(a, now) && cache.Get(c, now));
  assert(!cache.Get({"sogou", "nihao", 4}, now));
  assert(!cache.Get({"sogou", "ni'hao"}, now));
  assert(!cache.Get({"sogou", "nihao", 5, 2}, now));
  cache.Put(b, {}, std::chrono::seconds(15), now);
  assert(cache.Get(b, now)->empty()); // Empty result differs from a miss.
  assert(!cache.Get(b, now + std::chrono::seconds(15)));

  // Real public 'zhongguo' response, including full-match syllable end offsets.
  const uint8_t packet[] = {0x25,0,5,0,0,0,0,0,0,0,0,0,0,9,0,0,0,0,1,0,
      4,0,0x2d,0x4e,0xfd,0x56,4,0,0x8b,1,0x70,0,4,0,5,0,8,0,1};
  auto words = DecodeSogou(packet, sizeof(packet));
  assert(words.size() == 1 && words[0].consumed == 8 && words[0].utf16.size() == 4);
  for (size_t length = 0; length < sizeof(packet); ++length)
    assert(DecodeSogou(packet, length).empty());
  auto bad = std::vector<uint8_t>(std::begin(packet), std::end(packet));
  bad[32] = 0xff; assert(DecodeSogou(bad.data(), bad.size()).empty());
  assert(ValidPinyin("zhongguo") && ValidPinyin("xi'an"));
  assert(!ValidPinyin("http://foo") && !ValidPinyin("foo bar"));
  std::cout << "PASS: custom-first round robin, deduplication, TTL, LRU, cache key isolation, binary response bounds\n";
}
