import http from 'k6/http';
import { arrivalScenario, baseThresholds, ok, randomInt } from './lib/common.js';

const BASE = (__ENV.MAKEUP_BASE_URL || 'http://90.188.89.63:8085').replace(/\/$/, '');
const PEAK = Number(__ENV.LOAD_PEAK_RPS || 50);

export const options = {
  scenarios: {
    news_list: arrivalScenario('newsList', PEAK * 0.4, { endpoint: 'news_list' }),
    videos_list: arrivalScenario('videosList', PEAK * 0.3, { endpoint: 'videos_list' }),
    news_detail: arrivalScenario('newsDetail', PEAK * 0.3, { endpoint: 'news_detail' }),
  },
  thresholds: baseThresholds(),
};

export function setup() {
  const news = http.get(`${BASE}/api/news?page=0&size=20`);
  let newsIds = [];
  if (news.status === 200) {
    const body = news.json();
    const content = (body && body.content) || [];
    newsIds = content.map((n) => n.id).filter((id) => id != null);
  }

  const videos = http.get(`${BASE}/api/videos?page=0&size=20`);
  let videoIds = [];
  if (videos.status === 200) {
    const body = videos.json();
    const content = Array.isArray(body) ? body : (body && body.content) || [];
    videoIds = content.map((v) => v.id).filter((id) => id != null);
  }

  console.log(`setup: news=${newsIds.length} ids, videos=${videoIds.length} ids`);
  return { newsIds, videoIds };
}

export function newsList() {
  ok(http.get(`${BASE}/api/news?page=${randomInt(0, 3)}&size=20`), 'news list');
}

export function videosList() {
  ok(http.get(`${BASE}/api/videos?page=${randomInt(0, 3)}&size=20`), 'videos list');
}

export function newsDetail(data) {
  const ids = (data && data.newsIds) || [];
  if (ids.length === 0) return;
  const id = ids[randomInt(0, ids.length - 1)];
  ok(http.get(`${BASE}/api/news/${id}`), 'news detail');
}