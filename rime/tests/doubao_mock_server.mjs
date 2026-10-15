import http from 'node:http';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import zlib from 'node:zlib';
const port = Number(process.argv[2] || 18973);
const server = http.createServer();
function wsFrame(payload, opcode = 2) {
  const header = Buffer.alloc(payload.length < 126 ? 2 : 4);
  header[0] = 0x80 | opcode;
  if (payload.length < 126) header[1] = payload.length;
  else { header[1] = 126; header.writeUInt16BE(payload.length, 2); }
  return Buffer.concat([header, payload]);
}
function result(utterances, last = false) {
  const payload = zlib.gzipSync(Buffer.from(JSON.stringify({result:{utterances}})));
  const header = Buffer.from([0x11,last ? 0x93 : 0x91,0x11,0]);
  const sequence = Buffer.alloc(4); sequence.writeInt32BE(last ? -10 : 1);
  const length = Buffer.alloc(4); length.writeUInt32BE(payload.length);
  return wsFrame(Buffer.concat([header, sequence, length, payload]));
}
server.on('upgrade', (request, socket) => {
  assert.equal(request.headers['x-api-key'], 'test-key');
  assert.equal(request.headers['x-api-resource-id'], 'volc.seedasr.sauc.duration');
  assert.ok(request.headers['x-api-request-id']);
  const accept = crypto.createHash('sha1').update(request.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n');
  let pending = Buffer.alloc(0), packets = 0, configured = false;
  socket.on('error', () => {});
  socket.on('data', data => {
    pending = Buffer.concat([pending,data]);
    while (pending.length >= 2) {
      const opcode = pending[0] & 15, masked = (pending[1] & 128) !== 0;
      let length = pending[1] & 127, offset = 2;
      if (length === 126) { if (pending.length < 4) return; length = pending.readUInt16BE(2); offset = 4; }
      if (length === 127) { if (pending.length < 10) return; length = Number(pending.readBigUInt64BE(2)); offset = 10; }
      const maskLength = masked ? 4 : 0;
      if (pending.length < offset + maskLength + length) return;
      const mask = pending.subarray(offset, offset + maskLength);
      const payload = Buffer.from(pending.subarray(offset + maskLength, offset + maskLength + length));
      pending = pending.subarray(offset + maskLength + length);
      if (masked) for (let i=0;i<payload.length;i++) payload[i] ^= mask[i%4];
      if (opcode === 8) { socket.end(wsFrame(payload,8)); return; }
      if (opcode === 9) { socket.write(wsFrame(payload,10)); continue; }
      assert.equal(opcode,2); assert.ok(masked);
      assert.ok(payload.length >= 8);
      assert.equal(payload[0],0x11);
      const type = payload[1] >> 4, flags = payload[1] & 15;
      assert.equal(payload.readUInt32BE(4),payload.length-8);
      if (type === 1) {
        assert.equal(configured, false, 'configuration and hotwords sent only once');
        const config = JSON.parse(payload.subarray(8)); configured = true;
        assert.deepEqual(Object.keys(config.request.corpus), ['context']);
        const context = JSON.parse(config.request.corpus.context);
        assert.deepEqual(context, {hotwords:[{word:'AI助手'},{word:'Mac 电脑'}]});
        assert.equal(config.request.enable_nonstream,true); assert.equal(config.request.show_utterances,true);
        assert.equal(config.audio.rate,16000); assert.equal(config.audio.bits,16); assert.equal(config.audio.channel,1);
        if (request.url === '/error') {
          const error = Buffer.from('untrusted test-key echo');
          const header = Buffer.alloc(12); header.set([0x11,0xf0,0x10,0]); header.writeUInt32BE(45000001,4); header.writeUInt32BE(error.length,8);
          socket.write(wsFrame(Buffer.concat([header,error]))); continue;
        }
        if (request.url === '/disconnect') { socket.destroy(); return; }
        socket.write(result([]));
      } else if (type === 2) {
        assert.ok(configured);
        if (flags & 2) {
          assert.equal(payload.length,8);
          if (request.url === '/timeout') continue;
          assert.equal(packets,3);
          socket.write(result([{text:'你好。',start_time:0,end_time:600,definite:true},{text:'本地模拟服务。',start_time:600,end_time:900,definite:true}],true));
        } else {
          assert.ok(payload.length-8 <= 6400); packets++;
          if (request.url === '/timeout') continue;
          const text = packets === 1 ? '你' : packets === 2 ? '你好' : '你好。';
          socket.write(result([{text,start_time:0,end_time:600,definite:packets===3}]));
        }
      } else assert.fail('Unknown client frame');
    }
  });
});
server.listen(port,'127.0.0.1',()=>process.stdout.write('READY '+process.pid+'\n'));
