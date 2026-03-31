/**
 * page.js — HTML status page renderer
 */

export function statusColor(s) {
  return s === "ok" ? "#22c55e" : s === "degraded" ? "#f59e0b" : "#ef4444";
}

export function statusLabel(s) {
  return s === "ok" ? "Operational" : s === "degraded" ? "Degraded" : "Down";
}

export function renderHtml(services, overall, checkedAt) {
  const rows = services
    .map(
      (s) => `
      <tr>
        <td>${s.name}</td>
        <td><span class="badge" style="background:${statusColor(s.status)}">${statusLabel(s.status)}</span></td>
        <td>${s.latencyMs != null ? s.latencyMs + " ms" : "—"}</td>
        <td>${s.httpStatus ?? s.error ?? "—"}</td>
      </tr>`
    )
    .join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Paymentform Status</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: system-ui, sans-serif; background: #f9fafb; color: #111827; padding: 2rem 1rem; }
    header { max-width: 760px; margin: 0 auto 2rem; display: flex; align-items: center; gap: 1rem; }
    header h1 { font-size: 1.5rem; font-weight: 700; }
    .overall { display: inline-flex; align-items: center; gap: .5rem; padding: .4rem .9rem;
                border-radius: 9999px; font-weight: 600; font-size: .9rem;
                background: ${statusColor(overall)}22; color: ${statusColor(overall)}; border: 1px solid ${statusColor(overall)}44; }
    .card { max-width: 760px; margin: 0 auto; background: #fff; border: 1px solid #e5e7eb;
             border-radius: .75rem; overflow: hidden; box-shadow: 0 1px 3px #0001; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: .75rem 1rem; text-align: left; font-size: .9rem; }
    th { background: #f3f4f6; font-weight: 600; color: #374151; border-bottom: 1px solid #e5e7eb; }
    tr:not(:last-child) td { border-bottom: 1px solid #f3f4f6; }
    .badge { display: inline-block; padding: .2rem .6rem; border-radius: 9999px;
              color: #fff; font-size: .8rem; font-weight: 600; }
    footer { max-width: 760px; margin: 1.5rem auto 0; text-align: right; font-size: .8rem; color: #9ca3af; }
    @media (prefers-color-scheme: dark) {
      body { background: #111827; color: #f9fafb; }
      .card { background: #1f2937; border-color: #374151; }
      th { background: #374151; color: #d1d5db; border-color: #4b5563; }
      tr:not(:last-child) td { border-color: #374151; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Paymentform Status</h1>
    <span class="overall">${statusLabel(overall)}</span>
  </header>
  <div class="card">
    <table>
      <thead><tr><th>Service</th><th>Status</th><th>Latency</th><th>Detail</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>
  <footer>Last checked: ${checkedAt} &nbsp;·&nbsp; Auto-refreshes every 5 min</footer>
  <script>setTimeout(() => location.reload(), 300000);</script>
</body>
</html>`;
}
