/**
 * health.js — Service health probing logic
 */

export async function checkService(svc) {
  const start = Date.now();
  try {
    const res = await fetch(svc.health_url, {
      method: "GET",
      signal: AbortSignal.timeout(6000),
      headers: { "User-Agent": "paymentform-status/1.0" },
    });
    const latencyMs = Date.now() - start;
    const ok = res.status >= 200 && res.status < 300;
    return { name: svc.name, status: ok ? "ok" : "degraded", latencyMs, httpStatus: res.status };
  } catch (err) {
    return { name: svc.name, status: "down", latencyMs: Date.now() - start, error: err.message };
  }
}

export function overallStatus(services) {
  if (services.every((s) => s.status === "ok")) return "ok";
  if (services.some((s) => s.status === "down")) return "down";
  return "degraded";
}
