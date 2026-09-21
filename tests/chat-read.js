import http from 'k6/http';
import { authHeaders, JSON_HEADERS, arrivalScenario, baseThresholds, ok } from './lib/common.js';

const BASE = (__ENV.CHAT_BASE_URL || 'http://90.188.89.63:8086').replace(/\/$/, '');
const PEAK = Number(__ENV.LOAD_PEAK_RPS || 30);

export const options = {
  scenarios: {
    auth_me: arrivalScenario('authMe', PEAK * 0.1, { endpoint: 'auth_me' }),
    users_me: arrivalScenario('usersMe', PEAK * 0.15, { endpoint: 'users_me' }),
    users_sessions: arrivalScenario('usersSessions', PEAK * 0.15, { endpoint: 'users_sessions' }),
    users_search: arrivalScenario('usersSearch', PEAK * 0.15, { endpoint: 'users_search' }),
    chats: arrivalScenario('chats', PEAK * 0.15, { endpoint: 'chats' }),
    unread_all: arrivalScenario('unreadAll', PEAK * 0.1, { endpoint: 'unread_all' }),
    contacts: arrivalScenario('contacts', PEAK * 0.1, { endpoint: 'contacts' }),
    sync_status: arrivalScenario('syncStatus', PEAK * 0.1, { endpoint: 'sync_status' }),
  },
  thresholds: baseThresholds(),
};

// Read-only test still needs a valid JWT. Two options:
//   * set CHAT_USERNAME/CHAT_PASSWORD  -> logs in with an existing account (zero writes)
//   * otherwise                         -> registers one throwaway user per run (prefix `lt_`)
export function setup() {
  const username = __ENV.CHAT_USERNAME;
  const password = __ENV.CHAT_PASSWORD;

  if (username && password) {
    const payload = {
      username,
      password,
      deviceId: 'k6-loadtest',
      deviceName: 'k6',
      deviceType: 'WEB',
    };
    const res = http.post(`${BASE}/api/auth/login`, JSON.stringify(payload), { headers: JSON_HEADERS });
    if (res.status !== 200) {
      throw new Error(`login failed for "${username}": HTTP ${res.status} ${res.body}`);
    }
    console.log(`setup: logged in as existing user "${username}" (no writes)`);
    return { token: res.json('token') };
  }

  const stamp = Date.now();
  const user = `lt_${stamp}`;
  const payload = {
    username: user,
    email: `${user}@loadtest.local`,
    password: 'loadtest123',
    deviceId: 'k6-loadtest',
    deviceName: 'k6',
    deviceType: 'WEB',
  };
  const res = http.post(`${BASE}/api/auth/register`, JSON.stringify(payload), { headers: JSON_HEADERS });
  if (res.status !== 200) {
    throw new Error(`register failed: HTTP ${res.status} ${res.body}`);
  }
  console.log(`setup: created throwaway user "${user}" (see sql/cleanup-chat-loadtest.sql)`);
  return { token: res.json('token') };
}

function headers(data) {
  return authHeaders(data.token);
}

export function authMe(data) {
  ok(http.get(`${BASE}/api/auth/me`, { headers: headers(data) }), 'auth/me');
}

export function usersMe(data) {
  ok(http.get(`${BASE}/api/users/me`, { headers: headers(data) }), 'users/me');
}

export function usersSessions(data) {
  ok(http.get(`${BASE}/api/users/me/sessions`, { headers: headers(data) }), 'users/me/sessions');
}

export function unreadAll(data) {
  ok(http.get(`${BASE}/api/chats/unread-count/all`, { headers: headers(data) }), 'chats/unread-count/all');
}

export function usersSearch(data) {
  ok(http.get(`${BASE}/api/users/search?query=a&page=0&size=20`, { headers: headers(data) }), 'users/search');
}

export function chats(data) {
  ok(http.get(`${BASE}/api/chats`, { headers: headers(data) }), 'chats');
}

export function contacts(data) {
  ok(http.get(`${BASE}/api/contacts`, { headers: headers(data) }), 'contacts');
}

export function syncStatus(data) {
  ok(http.get(`${BASE}/api/sync/status`, { headers: headers(data) }), 'sync/status');
}