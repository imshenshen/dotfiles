#!/usr/bin/env python3
"""Probe cloud pinyin providers with public sample strings; never reads IME input."""
import argparse
import concurrent.futures
import functools
import json
import operator
import struct
import time
import urllib.error
import urllib.parse
import urllib.request


class HTTPSRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlparse(newurl).scheme != 'https':
            raise ValueError('HTTPS endpoint attempted to redirect to HTTP')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def request(url, timeout, payload=None):
    req = urllib.request.Request(url, data=payload, headers={
        'User-Agent': 'RimeCloudResearch/1.0',
        'Content-Type': 'application/octet-stream' if payload is not None else 'application/json',
    })
    opener = urllib.request.build_opener(HTTPSRedirectHandler())
    with opener.open(req, timeout=timeout) as response:
        return response.read(1024 * 1024)


def google(pinyin, timeout):
    query = urllib.parse.urlencode(dict(text=pinyin, itc='zh-t-i0-pinyin', num=5,
                                       cp=0, cs=1, ie='utf-8', oe='utf-8'))
    result = json.loads(request('https://inputtools.google.com/request?' + query, timeout))
    if result[0] != 'SUCCESS':
        raise ValueError('Google did not return SUCCESS')
    block = result[1][0]
    lengths = block[3].get('matched_length', [len(pinyin)] * len(block[1]))
    return [text for text, length in zip(block[1], lengths) if length == len(pinyin)]


def baidu(pinyin, timeout):
    query = urllib.parse.urlencode(dict(input=pinyin, inputtype='py', bg=0, ed=5,
                                       result='hanzi', resultcoding='utf-8', ch_en=0,
                                       clientinfo='web', version=1))
    result = json.loads(request('https://olime.baidu.com/py?' + query, timeout))
    if result.get('status') != 'T':
        raise ValueError('Baidu response: ' + json.dumps(result, ensure_ascii=False)[:512])
    return [entry[0] for entry in result['result'][0] if entry[1] == len(pinyin)]


def sogou(pinyin, timeout):
    # Protocol documented by hchunhui/librime-cloud/scripts/lua/sougou.lua.
    code = pinyin.encode('ascii')
    if len(code) > 245:
        raise ValueError('Sogou packet length exceeds one byte')
    token = b'\0\5\0\0\0\0\1'
    data = bytes([len(token) + len(code) + 3]) + token + bytes([len(code)]) + code
    data += bytes([functools.reduce(operator.xor, data, 0)])
    url = 'https://shouji.sogou.com/web_ime/mobile.php?durtot=0&h=000000000000000&r=store_mf_wandoujia&v=3.7'
    body = request(url, timeout, data)
    if len(body) < 22 or body[0] + 2 != len(body):
        raise ValueError('Sogou response is not a valid binary candidate packet')
    count = struct.unpack_from('<H', body, 18)[0]
    if not 0 < count <= 32:
        raise ValueError('Sogou candidate count outside protocol limits')
    offset, words = 20, []
    for _ in range(count):
        size = struct.unpack_from('<H', body, offset)[0]
        offset += 2
        words.append(body[offset:offset + size].decode('utf-16le'))
        offset += size
        size = struct.unpack_from('<H', body, offset)[0]
        offset += 2 + size
        size = struct.unpack_from('<H', body, offset)[0]
        offset += 3 + size
    return words[:5]


PROVIDERS = {'baidu': baidu, 'google': google, 'sogou': sogou}
SAMPLES = ['nihao', 'rengongzhineng', 'xinzhishengchanli', 'heishenhuawukong', 'damoxing']


def probe(provider, text, timeout):
    start = time.monotonic()
    result = dict(provider=provider, input=text)
    try:
        result['candidates'] = PROVIDERS[provider](text, timeout)
        result['ok'] = bool(result['candidates'])
    except Exception as error:
        result.update(ok=False, error=str(error))
    result['elapsed_ms'] = round((time.monotonic() - start) * 1000)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--providers', nargs='+', choices=PROVIDERS, default=list(PROVIDERS))
    parser.add_argument('--samples', nargs='+', default=SAMPLES)
    parser.add_argument('--timeout', type=float, default=3.0)
    args = parser.parse_args()
    if args.timeout <= 0 or any(not text.isascii() or not text.isalpha() or not text.islower() for text in args.samples):
        parser.error('Use lowercase ASCII pinyin and a positive timeout')
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for text in args.samples:
            futures = [pool.submit(probe, provider, text, args.timeout) for provider in args.providers]
            for future in concurrent.futures.as_completed(futures):
                print(json.dumps(future.result(), ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
