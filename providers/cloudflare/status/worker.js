/**
 * Paymentform Status Page — Cloudflare Worker entry point
 *
 * Routes:
 *   GET /        → HTML status page  (page.js)
 *   GET /status  → JSON { overall, checkedAt, services[] }
 *
 * Health probing is in health.js. Results are cached in KV for 5 minutes,
 * matching the NLB sustained-unhealthy alert window.
 */

import { checkService, overallStatus } from "./health.js";
import { renderHtml } from "./page.js";

// Match the NLB health check cadence — cache for 5 minutes.
const CACHE_TTL_SECONDS = 300;

function getServices() {
  try {
    return JSON.parse(SERVICES_JSON);
  } catch {
    return [];
  }
}

export default {
  async fetch(request, env) {
    const url    = new URL(request.url);
    const isJson = url.pathname === "/status";

    // Try KV cache first
    const cacheKey = "status:v1";
    let cached = null;
    if (env.STATUS_KV) {
      try { cached = await env.STATUS_KV.get(cacheKey, "json"); } catch {}
    }

    let services, overall, checkedAt;
    if (cached) {
      ({ services, overall, checkedAt } = cached);
    } else {
      services  = await Promise.all(getServices().map(checkService));
      overall   = overallStatus(services);
      checkedAt = new Date().toUTCString();

      if (env.STATUS_KV) {
        try {
          await env.STATUS_KV.put(cacheKey, JSON.stringify({ services, overall, checkedAt }), {
            expirationTtl: CACHE_TTL_SECONDS,
          });
        } catch {}
      }
    }

    const httpStatus = overall === "down" ? 503 : 200;

    if (isJson) {
      return new Response(JSON.stringify({ overall, checkedAt, services }, null, 2), {
        status: httpStatus,
        headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${CACHE_TTL_SECONDS}` },
      });
    }

    return new Response(renderHtml(services, overall, checkedAt), {
      status: httpStatus,
      headers: { "Content-Type": "text/html;charset=UTF-8", "Cache-Control": `public, max-age=${CACHE_TTL_SECONDS}` },
    });
  },
};
