import test from 'node:test';
import assert from 'node:assert/strict';

import { listDevices, setDeviceOnline } from '../src/session/store.js';

test('设备视图按账号过滤：不传账号不返回任何设备（无全局泄漏）', () => {
  setDeviceOnline('app-a', 'app', true, 'u-a');
  setDeviceOnline('app-b', 'app', true, 'u-b');
  setDeviceOnline('edge-a', 'edge', true, 'u-a');

  const forA = listDevices('u-a').map((d) => d.deviceId).sort();
  assert.deepEqual(forA, ['app-a', 'edge-a']);

  const forB = listDevices('u-b').map((d) => d.deviceId);
  assert.deepEqual(forB, ['app-b']);

  assert.deepEqual(listDevices('u-unknown'), []);
  assert.deepEqual(listDevices(), [], '不传账号时不返回全局视图');
});

test('设备条目保留账号归属，离线更新不丢账号', () => {
  setDeviceOnline('app-c', 'app', true, 'u-c');
  setDeviceOnline('app-c', 'app', false);

  const [device] = listDevices('u-c');
  assert.equal(device.deviceId, 'app-c');
  assert.equal(device.online, false);
  assert.equal(device.accountKey, 'u-c');
});