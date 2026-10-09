// macOS Rime plugin: network completions and Rime mutations meet on main queue.
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <rime_api.h>
#include <rime/candidate.h>
#include <rime/config.h>
#include <rime/context.h>
#include <rime/engine.h>
#include <rime/filter.h>
#include <rime/key_event.h>
#include <rime/language.h>
#include <rime/menu.h>
#include <rime/processor.h>
#include <rime/registry.h>
#include <rime/schema.h>
#include <rime/translation.h>
#include <rime/gear/translator_commons.h>
#include <rime/gear/table_translator.h>
#include <rime/gear/poet.h>
#include <rime/gear/unity_table_encoder.h>
#include <rime/dict/user_dictionary.h>
#include "core.h"

@interface RimeCloudHTTPSDelegate : NSObject <NSURLSessionTaskDelegate>
@end
@implementation RimeCloudHTTPSDelegate
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
    newRequest:(NSURLRequest*)request
    completionHandler:(void (^)(NSURLRequest*))completionHandler {
  completionHandler([request.URL.scheme isEqualToString:@"https"] ? request : nil);
}
@end

namespace cloud_pinyin {
using namespace rime;
struct Provider {
  string name;
  int timeout_ms;
  string label() const {
    if (name == "sogou") return "搜狗云";
    if (name == "google") return "Google 云";
    return "百度云";
  }
};

static NSString* NS(const string& s) {
  return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
}
static bool SafeWord(NSString* word) {
  return [word isKindOfClass:[NSString class]] && word.length > 0 && word.length <= 256 &&
      [word rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

static Words Parse(const string& provider, const string& code, NSData* data, int limit,
                   bool& success) {
  Words words;
  success = false;
  if (!data || data.length > 1024 * 1024) return words;
  if (provider == "sogou") {
    const auto* bytes = static_cast<const uint8_t*>(data.bytes);
    if (data.length < 20 || size_t(bytes[0]) + 2 != data.length) return words;
    auto parsed = DecodeSogou(bytes, data.length);
    // The protocol allows an empty list, but malformed nonempty lists fail.
    if (parsed.empty() && (bytes[18] != 0 || bytes[19] != 0)) return words;
    for (const auto& item : parsed) {
      if (item.consumed != code.size()) continue;
      NSString* word = [[NSString alloc] initWithBytes:item.utf16.data()
          length:item.utf16.size() encoding:NSUTF16LittleEndianStringEncoding];
      if (SafeWord(word)) words.push_back(word.UTF8String);
    }
    success = true;
  } else {
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (provider == "google") {
      if (![root isKindOfClass:[NSArray class]] || [root count] < 2 ||
          ![root[0] isEqual:@"SUCCESS"] || ![root[1] isKindOfClass:[NSArray class]] ||
          [root[1] count] == 0) return words;
      id block = root[1][0];
      if (![block isKindOfClass:[NSArray class]] || [block count] < 4 ||
          ![block[0] isEqual:NS(code)] || ![block[1] isKindOfClass:[NSArray class]] ||
          ![block[3] isKindOfClass:[NSDictionary class]]) return words;
      id lengths = block[3][@"matched_length"];
      if (![lengths isKindOfClass:[NSArray class]] || [lengths count] != [block[1] count])
        return words;
      for (NSUInteger i = 0; i < [lengths count]; ++i) {
        if ([lengths[i] isKindOfClass:[NSNumber class]] && [lengths[i] unsignedIntegerValue] == code.size() &&
            SafeWord(block[1][i])) words.push_back([block[1][i] UTF8String]);
      }
      success = true;
    } else if (provider == "baidu") {
      if (![root isKindOfClass:[NSDictionary class]] || ![root[@"status"] isEqual:@"T"] ||
          ![root[@"result"] isKindOfClass:[NSArray class]] || [root[@"result"] count] == 0)
        return words;
      id list = root[@"result"][0];
      if (![list isKindOfClass:[NSArray class]]) return words;
      for (id item in list) {
        if ([item isKindOfClass:[NSArray class]] && [item count] >= 2 &&
            [item[1] isKindOfClass:[NSNumber class]] && [item[1] unsignedIntegerValue] == code.size() &&
            SafeWord(item[0])) words.push_back([item[0] UTF8String]);
      }
      success = true;
    }
  }
  if (words.size() > size_t(limit)) words.resize(limit);
  return words;
}

static NSMutableURLRequest* Request(const Key& key, const Provider& provider) {
  NSURLComponents* url = [NSURLComponents new];
  url.scheme = @"https";
  NSMutableURLRequest* request;
  if (key.provider == "sogou") {
    // This adapter does not remove explicit syllable boundaries to guess positions.
    if (key.pinyin.find('\'') != string::npos) return nil;
    NSURL* endpoint = [NSURL URLWithString:@"https://shouji.sogou.com/web_ime/mobile.php?durtot=0&h=000000000000000&r=store_mf_wandoujia&v=3.7"];
    request = [NSMutableURLRequest requestWithURL:endpoint];
    std::vector<uint8_t> body{uint8_t(key.pinyin.size() + 10), 0, 5, 0, 0, 0, 0, 1,
                              uint8_t(key.pinyin.size())};
    body.insert(body.end(), key.pinyin.begin(), key.pinyin.end());
    uint8_t checksum = 0;
    for (auto byte : body) checksum ^= byte;
    body.push_back(checksum);
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSData dataWithBytes:body.data() length:body.size()];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
  } else {
    NSMutableArray<NSURLQueryItem*>* items = [NSMutableArray new];
    auto add = [&](NSString* name, NSString* value) {
      [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    };
    if (key.provider == "google") {
      url.host = @"inputtools.google.com"; url.path = @"/request";
      add(@"text", NS(key.pinyin)); add(@"itc", @"zh-t-i0-pinyin");
      add(@"num", NS(std::to_string(key.limit))); add(@"cp", @"0"); add(@"cs", @"1");
      add(@"ie", @"utf-8"); add(@"oe", @"utf-8");
    } else if (key.provider == "baidu") {
      url.host = @"olime.baidu.com"; url.path = @"/py";
      add(@"input", NS(key.pinyin)); add(@"inputtype", @"py"); add(@"bg", @"0");
      add(@"ed", NS(std::to_string(key.limit))); add(@"result", @"hanzi");
      add(@"resultcoding", @"utf-8"); add(@"ch_en", @"0"); add(@"clientinfo", @"web");
      add(@"version", @"1");
    } else return nil;
    url.queryItems = items;
    request = [NSMutableURLRequest requestWithURL:url.URL];
  }
  request.timeoutInterval = double(provider.timeout_ms) / 1000;
  request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  [request setValue:@"RimeCloudPinyin/1.0" forHTTPHeaderField:@"User-Agent"];
  return request;
}

class Network {
 public:
  Cache cache;
  struct Retry { int failures = 0; Clock::time_point after; };
  std::map<string, Retry> retries;
  std::map<Key, std::vector<std::function<void()>>> pending;
#ifdef RIME_CLOUD_TESTING
  struct Fixture { Words words; int delay_ms; bool success; };
  std::map<Key, Fixture> fixtures;
  std::map<Key, int> requests;
#endif
  static Network& Get() {
    // Lives for the process lifetime; NSURLSession callbacks can outlive a schema.
    static auto* singleton = new Network;
    return *singleton;
  }
  void Query(Key key, Provider provider, int ttl, int empty_ttl, std::function<void()> done) {
    // All cache, in-flight and retry access is on the input method's main thread.
    if (cache.Get(key)) { done(); return; }
    auto running = pending.find(key);
    if (running != pending.end()) { running->second.push_back(std::move(done)); return; }
    auto retry = retries.find(key.provider);
    if (retry != retries.end() && Clock::now() < retry->second.after) return;
    pending[key].push_back(std::move(done));
#ifdef RIME_CLOUD_TESTING
    ++requests[key];
    auto found = fixtures.find(key);
    auto fixture = found == fixtures.end() ? Fixture{{}, 5, true} : found->second;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, int64_t(fixture.delay_ms) * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ Complete(key, fixture.words, fixture.success, ttl, empty_ttl); });
#else
    NSMutableURLRequest* request = Request(key, provider);
    if (!request) { Complete(key, {}, true, ttl, empty_ttl); return; }
    NSURLSessionDataTask* task = [session_ dataTaskWithRequest:request
        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
      @autoreleasepool {
        bool success = false;
        Words words;
        if (!error && [response isKindOfClass:[NSHTTPURLResponse class]] &&
            [(NSHTTPURLResponse*)response statusCode] == 200 &&
            [response.URL.scheme isEqualToString:@"https"])
          words = Parse(key.provider, key.pinyin, data, key.limit, success);
        dispatch_async(dispatch_get_main_queue(), ^{ Complete(key, words, success, ttl, empty_ttl); });
      }
    }];
    [task resume];
    // NSURLSession's own timeout can behave as an inactivity timeout. Enforce
    // a total deadline as well, without ever blocking an input callback.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, int64_t(provider.timeout_ms) * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ if (task.state != NSURLSessionTaskStateCompleted) [task cancel]; });
#endif
  }
 private:
  Network() {
    NSURLSessionConfiguration* config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.URLCache = nil; config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil;
    config.HTTPMaximumConnectionsPerHost = 2;
    session_ = [NSURLSession sessionWithConfiguration:config delegate:[RimeCloudHTTPSDelegate new]
        delegateQueue:nil];
  }
  void Complete(const Key& key, Words words, bool success, int ttl, int empty_ttl) {
    auto found = pending.find(key);
    if (found == pending.end()) return;
    auto callbacks = std::move(found->second);
    pending.erase(found);
    if (success) {
      retries.erase(key.provider);
      auto lifetime = words.empty() ? empty_ttl : ttl;
      cache.Put(key, std::move(words), std::chrono::seconds(lifetime));
    } else {
      auto& retry = retries[key.provider];
      retry.failures = std::min(retry.failures + 1, 5);
      retry.after = Clock::now() + std::chrono::seconds(1 << retry.failures);
    }
    for (auto& callback : callbacks) callback();
  }
  __strong NSURLSession* session_;
};

struct Snapshot {
  string input, code;
  size_t caret = 0, start = 0, end = 0;
  bool operator==(const Snapshot& other) const {
    return input == other.input && code == other.code && caret == other.caret &&
           start == other.start && end == other.end;
  }
};

static string SegmentCode(Engine* engine, const string& input, const Segment& segment) {
  string code = input.substr(segment.start, segment.end - segment.start);
  if (segment.HasTag("reverse_lookup")) {
    string prefix, suffix;
    engine->schema()->config()->GetString("reverse_lookup/prefix", &prefix);
    engine->schema()->config()->GetString("reverse_lookup/suffix", &suffix);
    if (!prefix.empty() && code.compare(0, prefix.size(), prefix) == 0) code.erase(0, prefix.size());
    if (!suffix.empty() && code.size() >= suffix.size() &&
        code.compare(code.size() - suffix.size(), suffix.size(), suffix) == 0)
      code.resize(code.size() - suffix.size());
  }
  return code;
}

class CloudTableTranslator : public TableTranslator {
 public:
  explicit CloudTableTranslator(const Ticket& ticket) : TableTranslator(ticket) {}
  an<Translation> Query(const string& input, const Segment& segment) override {
    string code = segment.HasTag("reverse_lookup")
        ? SegmentCode(engine_, engine_->context()->input(), segment) : input;
    return TableTranslator::Query(code, segment);
  }
};

class State : public std::enable_shared_from_this<State> {
 public:
  Engine* engine;
  Snapshot snapshot;
  std::vector<Provider> providers;
  int debounce = 150, ttl = 300, empty_ttl = 15, limit = 5;
  uint64_t generation = 0, scheduled = 0;
  bool frozen = false;
  explicit State(const Ticket& ticket) : engine(ticket.engine) {
    Config* config = ticket.schema->config();
    auto number = [&](const string& name, int fallback, int min, int max) {
      int value = fallback; config->GetInt("cloud_pinyin/" + name, &value);
      return std::clamp(value, min, max);
    };
    debounce = number("debounce_ms", 150, 0, 1000);
    ttl = number("cache_ttl_seconds", 300, 1, 3600);
    empty_ttl = number("empty_ttl_seconds", 15, 1, 60);
    limit = number("max_candidates", 5, 1, 10);
    Network::Get().cache.SetCapacity(number("cache_capacity", 256, 1, 4096));
    if (auto list = config->GetList("cloud_pinyin/providers")) {
      std::set<string> seen;
      for (size_t i = 0; i < list->size(); ++i) {
        string path = "cloud_pinyin/providers/@" + std::to_string(i);
        string name; bool enabled = false; int timeout = 1000;
        config->GetString(path + "/name", &name);
        config->GetBool(path + "/enabled", &enabled);
        config->GetInt(path + "/timeout_ms", &timeout);
        if (enabled && (name == "sogou" || name == "google" || name == "baidu") && seen.insert(name).second)
          providers.push_back({name, std::clamp(timeout, 100, 5000)});
      }
    }
    if (auto component = UserDictionary::Require("user_dictionary")) {
      history_.reset(component->Create(Ticket(engine, "cloud_history")));
      if (history_) history_->Load();
    }
    commit_ = engine->context()->commit_notifier().connect([this](Context* ctx) {
      if (!history_ || !history_->loaded() || history_->readonly()) return;
      history_->NewTransaction();
      for (const auto& segment : ctx->composition()) {
        auto candidate = Candidate::GetGenuineCandidate(segment.GetSelectedCandidate());
        if (!candidate || candidate->type() != "cloud_pinyin") continue;
        string code = SegmentCode(engine, ctx->input(), segment);
        if (!ValidPinyin(code)) continue;
        DictEntry entry;
        entry.text = candidate->text(); entry.custom_code = code + " ";
        history_->UpdateEntry(entry, 1);
      }
      history_->CommitPendingTransaction();
    });
    option_ = engine->context()->option_update_notifier().connect(
        [this](Context*, const string& name) {
      if (name == "cloud_pinyin" || name == "ascii_mode" || name == "password" || name == "_password") {
        ++generation; frozen = false;
        Schedule();
      }
    });
    update_ = engine->context()->update_notifier().connect([this](Context* ctx) {
      // Mouse highlighting bypasses ProcessKeyEvent; keep the same freeze rule.
      if (!ctx->composition().empty() && ctx->composition().back().selected_index != 0)
        frozen = true;
    });
  }
  ~State() { commit_.disconnect(); option_.disconnect(); update_.disconnect(); }
  bool Enabled() const {
    auto* ctx = engine->context();
    return ctx->get_option("cloud_pinyin") && !ctx->get_option("ascii_mode") &&
        !ctx->get_option("password") && !ctx->get_option("_password");
  }
  bool Current(uint64_t token) const {
    auto* ctx = engine->context();
    if (generation != token || frozen || !Enabled() || ctx->input() != snapshot.input ||
        ctx->caret_pos() != snapshot.caret || ctx->composition().empty()) return false;
    const auto& seg = ctx->composition().back();
    return seg.start == snapshot.start && seg.end == snapshot.end && seg.status < Segment::kSelected &&
           seg.selected_index == 0 && (seg.HasTag("smart_pinyin") || seg.HasTag("reverse_lookup"));
  }
  void Observe(Snapshot next) {
    if (!(next == snapshot)) {
      snapshot = std::move(next); ++generation; frozen = false;
    }
  }
  void Schedule() {
    if (scheduled == generation || frozen || !Enabled() || providers.empty() ||
        !ValidPinyin(snapshot.code)) return;
    scheduled = generation;
    auto weak = weak_from_this();
    auto token = generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, int64_t(debounce) * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
      if (auto state = weak.lock(); state && state->Current(token)) {
        for (const auto& provider : state->providers) {
          Key key{provider.name, state->snapshot.code, state->limit};
          if (Network::Get().cache.Get(key)) continue;
          Network::Get().Query(key, provider, state->ttl, state->empty_ttl, [weak, token] {
            if (auto current = weak.lock(); current && current->Current(token)) {
              // Regenerate candidates first, then send the session-scoped frontend notification.
              auto* ctx = current->engine->context();
              ctx->RefreshNonConfirmedComposition();
              ctx->set_property("_refresh_ui", "value=" + std::to_string(token));
            }
          });
        }
      }
    });
  }
 private:
  the<UserDictionary> history_;
  connection commit_;
  connection option_;
  connection update_;
};

static std::map<Engine*, std::weak_ptr<State>> states;
static std::shared_ptr<State> GetState(const Ticket& ticket) {
  for (auto it = states.begin(); it != states.end();) {
    if (it->second.expired()) it = states.erase(it); else ++it;
  }
  if (auto state = states[ticket.engine].lock()) return state;
  auto state = std::make_shared<State>(ticket);
  states[ticket.engine] = state;
  return state;
}

class CloudProcessor : public Processor {
 public:
  explicit CloudProcessor(const Ticket& ticket) : Processor(ticket), state_(GetState(ticket)) {}
  ProcessResult ProcessKeyEvent(const KeyEvent& key) override {
    if (key.release()) return kNoop;
    const int code = key.keycode();
    const bool edit = !key.ctrl() && !key.alt() && !key.super() &&
        ((code >= 'a' && code <= 'z') || code == XK_BackSpace || code == XK_Delete ||
         code == XK_Left || code == XK_Right || code == XK_Home || code == XK_End);
    if (edit) {
      // Invalidate even when delete/retype returns to the same raw string.
      ++state_->generation;
      state_->frozen = false;
    } else if (engine_->context()->IsComposing()) {
      state_->frozen = true;
    }
    return kNoop;
  }
 private:
  std::shared_ptr<State> state_;
};

// Consume only a bounded local prefix. The remaining native translation stays
// lazy, and genuine candidates survive reordering and cloud deduplication.
class CloudTranslation : public Translation {
 public:
  CloudTranslation(CandidateList prefix, an<Translation> tail, std::set<string> seen)
      : prefix_(std::move(prefix)), tail_(std::move(tail)), seen_(std::move(seen)) { PrepareTail(); }
  bool Next() override {
    if (cursor_ < prefix_.size()) ++cursor_;
    else if (tail_ && !tail_->exhausted()) tail_->Next();
    PrepareTail();
    return !exhausted();
  }
  an<Candidate> Peek() override {
    if (cursor_ < prefix_.size()) return prefix_[cursor_];
    return tail_ && !tail_->exhausted() ? tail_->Peek() : nullptr;
  }
 private:
  void PrepareTail() {
    if (cursor_ < prefix_.size()) { set_exhausted(false); return; }
    while (tail_ && !tail_->exhausted()) {
      auto next = tail_->Peek();
      if (next && seen_.insert(next->text()).second) break;
      tail_->Next();
    }
    set_exhausted(!tail_ || tail_->exhausted());
  }
  CandidateList prefix_;
  an<Translation> tail_;
  std::set<string> seen_;
  size_t cursor_ = 0;
};

class CloudFilter : public Filter {
 public:
  explicit CloudFilter(const Ticket& ticket) : Filter(ticket), state_(GetState(ticket)) {}
  bool AppliesToSegment(Segment* segment) override {
    if (!segment->HasTag("smart_pinyin") && !segment->HasTag("reverse_lookup")) return false;
    auto* ctx = engine_->context();
    string code = SegmentCode(engine_, ctx->input(), *segment);
    if (!ValidPinyin(code)) return false;
    state_->Observe({ctx->input(), code, ctx->caret_pos(), segment->start, segment->end});
    return true;
  }
  an<Translation> Apply(an<Translation> input, CandidateList*) override {
    CandidateList custom, local;
    Words custom_words, local_words;
    std::map<string, an<Candidate>> genuine_local;
    // Custom translator has a high initial_quality, so its exact matches lead.
    for (size_t i = 0; i < 64 && !input->exhausted(); ++i) {
      auto candidate = input->Peek();
      if (candidate) {
        bool is_custom = false;
        for (auto& genuine : Candidate::GetGenuineCandidates(candidate)) {
          auto phrase = As<Phrase>(genuine);
          if (phrase && phrase->language() && phrase->language()->name() == "custom_phrase") is_custom = true;
        }
        auto& list = is_custom ? custom : local;
        auto& words = is_custom ? custom_words : local_words;
        list.push_back(candidate); words.push_back(candidate->text());
        if (candidate->start() == state_->snapshot.start && candidate->end() == state_->snapshot.end)
          genuine_local.emplace(candidate->text(), candidate);
      }
      input->Next();
    }
    std::vector<Words> cloud;
    if (state_->Enabled()) {
      for (const auto& provider : state_->providers) {
        auto* cached = Network::Get().cache.Get({provider.name, state_->snapshot.code, state_->limit});
        cloud.push_back(cached ? *cached : Words{});
      }
      state_->Schedule();
    }
    auto picks = Interleave(custom_words, local_words, cloud);
    CandidateList result;
    std::set<string> seen;
    for (const auto& pick : picks) {
      an<Candidate> candidate;
      if (pick.source == -2) candidate = custom[pick.index];
      else if (pick.source == -1) candidate = local[pick.index];
      else {
        string comment = state_->providers[pick.source].label();
        auto native = genuine_local.find(pick.text);
        if (native != genuine_local.end()) {
          // Prefer the native object's learning semantics even when its text
          // first appears in a cloud slot.
          candidate = New<ShadowCandidate>(native->second, native->second->type(), "", comment, false);
        } else {
          candidate = New<SimpleCandidate>("cloud_pinyin", state_->snapshot.start, state_->snapshot.end,
              pick.text, comment, state_->snapshot.code);
        }
      }
      if (candidate->start() == state_->snapshot.start && candidate->end() == state_->snapshot.end) {
        string sources;
        for (size_t p = 0; p < cloud.size(); ++p) {
          if (std::find(cloud[p].begin(), cloud[p].end(), pick.text) != cloud[p].end()) {
            if (!sources.empty()) sources += "·";
            sources += state_->providers[p].label();
          }
        }
        if (!sources.empty()) {
          if (pick.source < 0 && !candidate->comment().empty()) sources = candidate->comment() + " · " + sources;
          candidate = New<ShadowCandidate>(candidate, candidate->type(), "", sources, false);
        }
      }
      result.push_back(candidate); seen.insert(pick.text);
    }
    return New<CloudTranslation>(std::move(result), input, std::move(seen));
  }
 private:
  std::shared_ptr<State> state_;
};
} // namespace cloud_pinyin

static void rime_cloud_pinyin_initialize() {
  auto& registry = rime::Registry::instance();
  registry.Register("cloud_pinyin_filter", new rime::Component<cloud_pinyin::CloudFilter>);
  registry.Register("cloud_pinyin_processor", new rime::Component<cloud_pinyin::CloudProcessor>);
  registry.Register("cloud_table_translator", new rime::Component<cloud_pinyin::CloudTableTranslator>);
}
static void rime_cloud_pinyin_finalize() {}
RIME_REGISTER_MODULE(cloud_pinyin)

#ifdef RIME_CLOUD_TESTING
// Test-only entry points are absent from the installed production plugin.
extern "C" void CloudTestFixture(const char* provider, const char* code, const char* json,
                                  int delay_ms, bool success) {
  auto& network = cloud_pinyin::Network::Get();
  NSData* data = [cloud_pinyin::NS(json) dataUsingEncoding:NSUTF8StringEncoding];
  NSArray* list = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  cloud_pinyin::Words words;
  for (NSString* word in list) words.push_back(word.UTF8String);
  network.fixtures[{provider, code, 5}] = {words, delay_ms, success};
}
extern "C" int CloudTestRequests(const char* provider, const char* code) {
  return cloud_pinyin::Network::Get().requests[{provider, code, 5}];
}
extern "C" void CloudTestReset() {
  auto& network = cloud_pinyin::Network::Get();
  network.cache.Clear(); network.retries.clear(); network.requests.clear(); network.fixtures.clear();
}
#endif
