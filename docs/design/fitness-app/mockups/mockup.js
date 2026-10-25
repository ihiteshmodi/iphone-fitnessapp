const G = "#2ee887", TRACK = "#232a26";

function ring(pct, size, stroke, label, sub, color) {
  const r = (size - stroke) / 2, c = 2 * Math.PI * r, col = color || G;
  const fs = size > 80 ? size * 0.22 : size * 0.26;
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
    <circle cx="${size/2}" cy="${size/2}" r="${r}" fill="none" stroke="${TRACK}" stroke-width="${stroke}"/>
    <circle cx="${size/2}" cy="${size/2}" r="${r}" fill="none" stroke="${col}" stroke-width="${stroke}" stroke-linecap="round"
      stroke-dasharray="${c * pct} ${c}" transform="rotate(-90 ${size/2} ${size/2})"/>
    ${label ? `<text x="50%" y="${sub ? "49%" : "54%"}" text-anchor="middle" fill="#f2f5f3" font-weight="700" font-size="${fs}">${label}</text>` : ""}
    ${sub ? `<text x="50%" y="66%" text-anchor="middle" fill="#8a9690" font-size="${size*0.1}">${sub}</text>` : ""}
  </svg>`;
}

function renderRings() {
  document.querySelectorAll("[data-ring]").forEach(el => {
    el.innerHTML = ring(+el.dataset.ring, +el.dataset.size, +el.dataset.stroke, el.dataset.label, el.dataset.sub, el.dataset.color);
    el.style.flex = "none";
  });
}

function sparkPoints(vals, w, h, pad) {
  const min = Math.min(...vals), max = Math.max(...vals), span = (max - min) || 1;
  return vals.map((v, i) => [pad + i * (w - 2 * pad) / (vals.length - 1), h - pad - (v - min) / span * (h - 2 * pad)]);
}

function renderSparks() {
  document.querySelectorAll("svg[data-spark]").forEach(svg => {
    const vals = svg.dataset.spark.split(",").map(Number);
    const inCard = !!svg.closest(".ex"), w = inCard ? 120 : +svg.getAttribute("width"), h = inCard ? 18 : +svg.getAttribute("height");
    svg.setAttribute("width", w); svg.setAttribute("height", h);
    const flat = Math.max(...vals) === Math.min(...vals);
    const pts = sparkPoints(vals, w, h, 3), last = pts[pts.length - 1];
    const down = vals[vals.length - 1] < vals[0];
    const col = flat ? "#f5c542" : down ? "#ff6b6b" : G;
    svg.innerHTML = `<polyline points="${pts.map(p => p.join(",")).join(" ")}" fill="none" stroke="${col}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <circle cx="${last[0]}" cy="${last[1]}" r="3" fill="${col}"/>`;
  });
}

function lineChart(id, series, w, h, opts) {
  const el = document.getElementById(id);
  if (!el) return;
  const all = series.flatMap(s => s.vals), min = Math.min(...all) - (opts.padY || 2), max = Math.max(...all) + (opts.padY || 2);
  const n = series[0].vals.length, L = 8, R = 8, T = 14, B = 22;
  const x = i => L + i * (w - L - R) / (n - 1), y = v => T + (max - v) / (max - min) * (h - T - B);
  let out = `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`;
  for (let g = 0; g < 4; g++) { const gy = T + g * (h - T - B) / 3; out += `<line x1="${L}" x2="${w - R}" y1="${gy}" y2="${gy}" stroke="${TRACK}"/>`; }
  series.forEach((s, k) => {
    const pts = s.vals.map((v, i) => [x(i), y(v)]);
    if (opts.area && k === 0) out += `<polygon points="${pts.map(p => p.join(",")).join(" ")} ${x(n-1)},${h-B} ${x(0)},${h-B}" fill="${s.color}" opacity="0.12"/>`;
    out += `<polyline points="${pts.map(p => p.join(",")).join(" ")}" fill="none" stroke="${s.color}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" ${s.dash ? 'stroke-dasharray="4 4"' : ""}/>`;
    pts.forEach((p, i) => {
      out += `<circle cx="${p[0]}" cy="${p[1]}" r="3.6" fill="${s.hollow ? "#141816" : s.color}" stroke="${s.color}" stroke-width="2"/>`;
      if (s.labels) out += `<text x="${p[0]}" y="${p[1] - 9}" text-anchor="middle" font-size="10" fill="${s.color}">${s.labels[i]}</text>`;
    });
  });
  (opts.xlabels || []).forEach((t, i) => { out += `<text x="${x(i)}" y="${h - 5}" text-anchor="middle" font-size="10" fill="#8a9690">${t}</text>`; });
  el.innerHTML = out + "</svg>";
}

const SESSIONS = ["12 Sep", "19 Sep", "26 Sep", "3 Oct", "10 Oct", "18 Oct"];

document.addEventListener("DOMContentLoaded", () => { renderRings(); renderSparks(); if (window.drawCharts) window.drawCharts(); });
