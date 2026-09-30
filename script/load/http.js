// HTTP load test for POST /conversations/:id/messages (rate limiter -> token lock -> insert -> enqueue).
//
//   k6 run script/load/http.js
//   RATE=15 HOLD=60s BASE_URL=http://localhost:3000 k6 run script/load/http.js
//
// Needs tmp/load/users.json from script/load/http_setup.rb. Users rotate per request, so each
// sends RATE * 60 / users messages a minute; keep that under RateLimiter::LIMIT (10) unless
// the goal is to measure the limiter itself.

import http from "k6/http";
import exec from "k6/execution";
import { check } from "k6";
import { Counter } from "k6/metrics";
import { SharedArray } from "k6/data";

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";
const RATE = Number(__ENV.RATE || 15);
const RAMP = __ENV.RAMP || "30s";
const HOLD = __ENV.HOLD || "60s";
const USER_LIMIT_PER_MIN = 10;

const users = new SharedArray("users", () => JSON.parse(open("../../tmp/load/users.json")));

const byStatus = {
  ok: new Counter("status_200"),
  rateLimited: new Counter("status_429"),
  noTokens: new Counter("status_402"),
  csrf: new Counter("status_422"),
  serverError: new Counter("status_5xx"),
};

export const options = {
  scenarios: {
    messages: {
      executor: "ramping-arrival-rate",
      startRate: 1,
      timeUnit: "1s",
      preAllocatedVUs: 20,
      maxVUs: 200,
      stages: [
        { target: RATE, duration: RAMP },
        { target: RATE, duration: HOLD },
      ],
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{expected_response:true}": ["p(95)<500"],
  },
  summaryTrendStats: ["avg", "min", "med", "p(90)", "p(95)", "p(99)", "max"],
};

export function setup() {
  const perUserPerMin = (RATE * 60) / users.length;
  if (perUserPerMin > USER_LIMIT_PER_MIN) {
    console.warn(`RATE=${RATE} gives ${perUserPerMin.toFixed(1)} msgs/min per user: expect 429s.`);
  }
}

export default function () {
  const user = users[exec.scenario.iterationInTest % users.length];

  const res = http.post(
    `${BASE_URL}/conversations/${user.conversation_id}/messages`,
    { "message[content]": `load ${exec.scenario.iterationInTest}` },
    {
      headers: {
        Cookie: user.cookie,
        "X-CSRF-Token": user.csrf,
        Accept: "text/vnd.turbo-stream.html",
      },
      tags: { name: "POST /messages" },
    },
  );

  if (res.status === 200) byStatus.ok.add(1);
  else if (res.status === 429) byStatus.rateLimited.add(1);
  else if (res.status === 402) byStatus.noTokens.add(1);
  else if (res.status === 422) byStatus.csrf.add(1);
  else if (res.status >= 500) byStatus.serverError.add(1);

  check(res, {
    "status 200": (r) => r.status === 200,
    "turbo stream appended": (r) => r.body && r.body.includes('<turbo-stream action="append"'),
  });
}
