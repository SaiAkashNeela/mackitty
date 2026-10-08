/**
 * MacKitty — interactive app replica & site controller.
 * The demo window mirrors SimpleDashboardView.swift / TrayMiniDashboardView.swift
 * (light design system from Theme.swift).
 */

function initAppDemo() {
  const win = document.getElementById("mac-window");
  const frame = document.getElementById("mac-window-frame");
  if (!win || !frame) return;

  const $ = (id) => document.getElementById(id);
  const SVG_NS = "http://www.w3.org/2000/svg";
  const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  let reduced = motionQuery.matches;

  const C = {
    accent: "#0D9488",
    accentStrong: "#0F766E",
    success: "#16A34A",
    warning: "#D97706",
    danger: "#DC2626",
    slate: "#6B7890",
    canvasDeep: "#ECECEF",
  };
  const CATEGORY_COLORS = [C.accent, "#2563EB", "#7C3AED", C.warning, "#64738C"];
  const TOTAL_GB = 494.4;

  // Mirrors the real cleanup targets in NativeCleanerService.swift.
  const CATEGORIES = [
    { id: "xcode", name: "Xcode Derived Data", path: "~/Library/Developer/Xcode/DerivedData", gb: 18.4 },
    { id: "appcache", name: "Other App Caches", path: "~/Library/Caches", gb: 6.2 },
    { id: "chrome", name: "Google Chrome Cache", path: "~/Library/Caches/Google/Chrome", gb: 3.1 },
    { id: "safari", name: "Safari Cache", path: "~/Library/Caches/com.apple.Safari", gb: 1.9 },
    { id: "logs", name: "User App Logs", path: "~/Library/Logs", gb: 1.4 },
    { id: "npm", name: "npm & Node Cache", path: "~/.npm", gb: 0.98 },
  ];

  const SCAN_PATHS = [
    "~/Library/Caches/com.apple.Safari",
    "~/Library/Developer/Xcode/DerivedData/MacKitty-bdlcm/Build/Intermediates.noindex",
    "~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex",
    "~/Library/Caches/Google/Chrome/Default/Cache",
    "~/Library/Caches/com.spotify.client/Data",
    "~/Library/Logs/DiagnosticReports",
    "~/.npm/_cacache/content-v2/sha512",
    "~/Library/Caches/org.mozilla.firefox/Profiles",
  ];

  const state = {
    tab: "clean",
    screen: "welcome",
    usedGB: 356.0,
    results: null,
    sort: "size",
    history: [],
    totalCleanedGB: 0,
    permissionGranted: false,
    heroPaused: reduced,
    inView: true,
  };

  /* ---------- helpers ---------- */
  const round2 = (n) => Math.round(n * 100) / 100;
  function fmt(gb) {
    if (gb <= 0) return "0 KB";
    if (gb < 1) return Math.round(gb * 1000) + " MB";
    return Number(gb.toFixed(2)) + " GB";
  }
  function esc(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }
  const freeGB = () => TOTAL_GB - state.usedGB;
  const usedRatio = () => state.usedGB / TOTAL_GB;
  const reclaimableGB = () => (state.results ? state.results.reduce((s, r) => s + r.gb, 0) : 0);
  const selectedItems = () => (state.results ? state.results.filter((r) => r.selected) : []);
  const selectedGB = () => selectedItems().reduce((s, r) => s + r.gb, 0);
  const loadColor = (r) => (r > 0.85 ? C.danger : r > 0.65 ? C.warning : C.accent);
  function svgEl(tag, attrs) {
    const el = document.createElementNS(SVG_NS, tag);
    for (const k in attrs) el.setAttribute(k, attrs[k]);
    return el;
  }
  /** Converts a pointer position to the window's unscaled coordinate space. */
  function localPoint(el, e) {
    const rect = el.getBoundingClientRect();
    const sx = rect.width / (el.clientWidth || rect.width || 1);
    const sy = rect.height / (el.clientHeight || rect.height || 1);
    return { x: (e.clientX - rect.left) / sx, y: (e.clientY - rect.top) / sy };
  }

  /* ---------- window scaling ---------- */
  function fitWindow() {
    const s = Math.min(1, frame.clientWidth / 1120) || 1;
    win.style.setProperty("--mk-scale", s.toFixed(4));
  }
  fitWindow();
  if ("ResizeObserver" in window) new ResizeObserver(fitWindow).observe(frame);
  else window.addEventListener("resize", fitWindow);

  /* ---------- screens & tabs ---------- */
  const SCREEN_IDS = {
    welcome: "screen-welcome",
    scanning: "screen-scanning",
    triage: "screen-triage",
    cleaning: "screen-cleaning",
    summary: "screen-summary",
  };
  const STATUS = {
    welcome: ["Idle", ""],
    scanning: ["Scanning", "is-busy"],
    triage: ["Ready to clean", "is-ready"],
    cleaning: ["Cleaning", "is-busy"],
    summary: ["Complete", "is-done"],
  };
  const tabButtons = win.querySelectorAll(".mk-topseg .mk-seg-btn");

  function showActive() {
    const activeId = state.tab === "apps" ? "screen-apps" : SCREEN_IDS[state.screen];
    win.querySelectorAll(".mk-screen").forEach((s) => s.classList.toggle("active", s.id === activeId));
    tabButtons.forEach((b) => {
      const on = b.dataset.appTab === state.tab;
      b.classList.toggle("active", on);
      b.setAttribute("aria-selected", on ? "true" : "false");
    });
    const [label, cls] = STATUS[state.screen];
    $("window-status-label").textContent = label;
    $("window-status-dot").className = "mk-status-dot " + cls;
    if (activeId === "screen-welcome") {
      sparks.forEach((s) => s.draw());
      renderHistory();
    }
    updateVideos();
    renderTray();
  }

  function setScreen(name) {
    state.screen = name;
    state.tab = "clean";
    showActive();
  }

  function setTab(tab) {
    state.tab = tab;
    showActive();
  }

  tabButtons.forEach((b) => b.addEventListener("click", () => setTab(b.dataset.appTab)));

  /* ---------- videos ---------- */
  const hero = $("mk-hero");
  const heroVideo = $("mk-hero-video");
  const bannerVideos = win.querySelectorAll(".mk-banner-video");

  function safePlay(v) {
    const p = v.play();
    if (p && typeof p.catch === "function") p.catch(() => {});
  }

  function updateVideos() {
    const heroVisible = state.tab === "clean" && state.screen === "welcome" && state.inView;
    if (heroVisible && !state.heroPaused) safePlay(heroVideo);
    else heroVideo.pause();
    hero.classList.toggle("is-paused", state.heroPaused);
    const btn = $("mk-video-toggle");
    const label = state.heroPaused ? "Play animation" : "Pause animation";
    btn.title = label;
    btn.setAttribute("aria-label", label);

    bannerVideos.forEach((v) => {
      const active = v.closest(".mk-screen").classList.contains("active") && state.tab === "clean" && state.inView;
      if (active && !reduced) {
        if (!v.getAttribute("src")) v.setAttribute("src", v.dataset.src);
        safePlay(v);
      } else {
        v.pause();
      }
    });
  }

  if (reduced) heroVideo.removeAttribute("autoplay");
  $("mk-video-toggle").addEventListener("click", (e) => {
    e.stopPropagation();
    state.heroPaused = !state.heroPaused;
    updateVideos();
  });

  if ("IntersectionObserver" in window) {
    new IntersectionObserver((entries) => {
      state.inView = entries[0].isIntersecting;
      updateVideos();
    }).observe(frame);
  }

  // Cursor parallax: the scene drifts opposite to the pointer.
  hero.addEventListener("pointermove", (e) => {
    if (reduced) return;
    const p = localPoint(hero, e);
    const dx = (p.x / hero.clientWidth - 0.5) * -20;
    const dy = (p.y / hero.clientHeight - 0.5) * -12;
    heroVideo.style.setProperty("--px", dx.toFixed(1) + "px");
    heroVideo.style.setProperty("--py", dy.toFixed(1) + "px");
  });
  hero.addEventListener("pointerleave", () => {
    heroVideo.style.setProperty("--px", "0px");
    heroVideo.style.setProperty("--py", "0px");
  });

  /* ---------- disk: hero, donut, tray ---------- */
  function diskTone(r) {
    if (r > 0.9) return { hero: "#FF6B6B", ui: C.danger, headline: "Your Mac is almost out of space.", tray: "Storage almost full" };
    if (r > 0.7) return { hero: "#FFB84D", ui: C.warning, headline: "Your Mac is filling up.", tray: "Storage filling up" };
    return { hero: "#5EE6CC", ui: C.accent, headline: "Your Mac is in good shape.", tray: "Storage healthy" };
  }

  function renderDisk() {
    const r = usedRatio();
    const pct = Math.round(r * 100);
    const tone = diskTone(r);
    hero.style.setProperty("--hero-color", tone.hero);
    $("hero-status").textContent = `Macintosh HD · ${pct}% used`;
    $("hero-title").textContent = tone.headline;
    $("hero-sub").textContent = `${fmt(freeGB())} free of ${fmt(TOTAL_GB)}. A scan finds caches, logs and leftovers that are safe to remove.`;
    $("hero-bar-fill").style.width = pct + "%";
    $("donut-capacity").textContent = fmt(TOTAL_GB);
    $("tray-menubar-pct").textContent = pct + "%";
    renderDonut();
  }

  /* Donut chart (SectorMark with inner radius 0.7, angular inset 1.5°) */
  const donutSvg = $("mk-donut");
  const donutCard = donutSvg.closest(".mk-donut-card");
  const legend = $("mk-legend");
  let donutSlices = [];
  let donutSel = null;

  function sectorPath(a0, a1, rIn, rOut) {
    const pt = (a, r) => {
      const rad = ((a - 90) * Math.PI) / 180;
      return (100 + r * Math.cos(rad)).toFixed(2) + " " + (100 + r * Math.sin(rad)).toFixed(2);
    };
    const large = a1 - a0 > 180 ? 1 : 0;
    return `M ${pt(a0, rOut)} A ${rOut} ${rOut} 0 ${large} 1 ${pt(a1, rOut)} L ${pt(a1, rIn)} A ${rIn} ${rIn} 0 ${large} 0 ${pt(a0, rIn)} Z`;
  }

  function renderDonut() {
    const reclaim = reclaimableGB();
    donutSlices = [{ id: "Used", gb: state.usedGB - reclaim, color: C.slate }];
    if (reclaim > 0) donutSlices.push({ id: "Reclaimable", gb: reclaim, color: C.accent });
    donutSlices.push({ id: "Free", gb: freeGB(), color: C.canvasDeep });
    const total = donutSlices.reduce((s, x) => s + x.gb, 0);
    let a = 0;
    donutSvg.textContent = "";
    legend.textContent = "";
    donutSlices.forEach((sl) => {
      const span = (sl.gb / total) * 360;
      sl.a0 = a + 0.75;
      sl.a1 = a + span - 0.75;
      a += span;
      sl.path = svgEl("path", { fill: sl.color, stroke: sl.color });
      const t = svgEl("title", {});
      t.textContent = `${sl.id}: ${fmt(sl.gb)}`;
      sl.path.appendChild(t);
      sl.path.addEventListener("pointerenter", () => selectSlice(sl.id));
      sl.path.addEventListener("pointerleave", () => selectSlice(null));
      donutSvg.appendChild(sl.path);

      const row = document.createElement("div");
      row.className = "mk-legend-row";
      row.innerHTML = `<span class="mk-swatch" style="background:${sl.color}"></span><span>${sl.id}</span><b>${fmt(sl.gb)}</b>`;
      row.addEventListener("pointerenter", () => selectSlice(sl.id));
      row.addEventListener("pointerleave", () => selectSlice(null));
      sl.row = row;
      legend.appendChild(row);
    });
    $("donut-note").style.display = reclaim > 0 ? "none" : "";
    selectSlice(donutSel && donutSlices.some((s) => s.id === donutSel) ? donutSel : null);
  }

  function selectSlice(id) {
    donutSel = id;
    donutSlices.forEach((sl) => {
      const on = sl.id === id;
      sl.path.setAttribute("d", sectorPath(sl.a0, sl.a1, 70, on ? 100 : 94));
      sl.path.style.opacity = id === null || on ? 1 : 0.45;
      sl.row.classList.toggle("sel", on);
    });
    donutCard.classList.toggle("has-sel", id !== null);
    const sel = donutSlices.find((s) => s.id === id);
    $("donut-big").textContent = sel ? fmt(sel.gb) : Math.round(usedRatio() * 100) + "%";
    $("donut-small").textContent = sel ? sel.id : "used";
  }

  /* ---------- live metrics ---------- */
  const metrics = {
    cpu: { value: 0.28, history: [], min: 0.08, max: 0.62, step: 0.07 },
    mem: { value: 0.77, history: [], min: 0.72, max: 0.82, step: 0.012 },
  };
  for (const key in metrics) {
    const m = metrics[key];
    let v = m.value;
    for (let i = 0; i < 40; i++) {
      v = Math.min(m.max, Math.max(m.min, v + (Math.random() - 0.5) * m.step * 2));
      m.history.push(v);
    }
    m.history[39] = m.value;
  }

  const faces = {
    cpu: [
      () => [Math.round(metrics.cpu.value * 100) + "%", "load"],
      () => ["10 cores", "Apple M4"],
    ],
    mem: [
      () => [(metrics.mem.value * 16).toFixed(2) + " GB", "used"],
      () => [Math.round(metrics.mem.value * 100) + "%", "pressure"],
      () => [((1 - metrics.mem.value) * 16).toFixed(2) + " GB", "free"],
    ],
  };
  const faceIndex = { cpu: 0, mem: 0 };

  function renderMetricText(key) {
    const [v, cap] = faces[key][faceIndex[key] % faces[key].length]();
    $(key + "-val").textContent = v;
    $(key + "-cap").textContent = cap;
  }

  class Sparkline {
    constructor(container, key) {
      this.el = container;
      this.key = key;
      const gid = "mkgrad-" + key;
      this.svg = svgEl("svg", { "aria-hidden": "true" });
      const defs = svgEl("defs", {});
      this.grad = svgEl("linearGradient", { id: gid, x1: "0", y1: "0", x2: "0", y2: "1" });
      this.stop0 = svgEl("stop", { offset: "0", "stop-opacity": "0.22" });
      this.stop1 = svgEl("stop", { offset: "1", "stop-opacity": "0" });
      this.grad.append(this.stop0, this.stop1);
      defs.appendChild(this.grad);
      this.area = svgEl("path", { fill: `url(#${gid})` });
      this.line = svgEl("path", { fill: "none", "stroke-width": "1.5", "stroke-linecap": "round", "stroke-linejoin": "round" });
      this.cursor = svgEl("line", { stroke: "rgba(17,19,25,0.14)", "stroke-width": "1", visibility: "hidden" });
      this.dot = svgEl("circle", { r: "3", visibility: "hidden" });
      this.svg.append(defs, this.area, this.line, this.cursor, this.dot);
      this.tip = document.createElement("div");
      this.tip.className = "mk-spark-tip";
      this.tip.hidden = true;
      container.append(this.svg, this.tip);
      this.hover = null;
      container.addEventListener("pointermove", (e) => {
        const w = container.clientWidth || 1;
        const n = metrics[key].history.length;
        const x = localPoint(container, e).x;
        this.hover = Math.min(n - 1, Math.max(0, Math.round((x / w) * (n - 1))));
        this.draw();
      });
      container.addEventListener("pointerleave", () => {
        this.hover = null;
        this.draw();
      });
    }

    draw() {
      const w = this.el.clientWidth;
      const h = this.el.clientHeight;
      if (!w || !h) return;
      const vals = metrics[this.key].history;
      const color = loadColor(metrics[this.key].value);
      const step = w / (vals.length - 1);
      const pts = vals.map((v, i) => [i * step, 2 + (1 - Math.min(Math.max(v, 0), 1)) * (h - 4)]);
      const line = pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" ");
      this.line.setAttribute("d", line);
      this.line.setAttribute("stroke", color);
      this.area.setAttribute("d", `M0 ${h} ${line.replace(/^M/, "L")} L${w} ${h} Z`);
      this.stop0.setAttribute("stop-color", color);
      this.stop1.setAttribute("stop-color", color);
      if (this.hover === null) {
        this.cursor.setAttribute("visibility", "hidden");
        this.dot.setAttribute("visibility", "hidden");
        this.tip.hidden = true;
        return;
      }
      const [x, y] = pts[this.hover];
      this.cursor.setAttribute("x1", x);
      this.cursor.setAttribute("x2", x);
      this.cursor.setAttribute("y1", 0);
      this.cursor.setAttribute("y2", h);
      this.cursor.setAttribute("visibility", "visible");
      this.dot.setAttribute("cx", x);
      this.dot.setAttribute("cy", y);
      this.dot.setAttribute("fill", color);
      this.dot.setAttribute("visibility", "visible");
      this.tip.hidden = false;
      this.tip.textContent = Math.round(vals[this.hover] * 100) + "%";
      this.tip.style.left = Math.min(Math.max(x, 16), w - 16) + "px";
      this.tip.style.top = Math.max(y - 6, 14) + "px";
    }
  }

  const sparks = [new Sparkline($("spark-cpu"), "cpu"), new Sparkline($("spark-mem"), "mem")];

  ["cpu", "mem"].forEach((key) => {
    $("tile-" + key).addEventListener("click", () => {
      faceIndex[key]++;
      renderMetricText(key);
    });
    renderMetricText(key);
  });

  function drawTraySpark(svg, key) {
    const vals = metrics[key].history.slice(-20);
    const color = loadColor(metrics[key].value);
    const step = 70 / (vals.length - 1);
    const line = vals.map((v, i) => (i ? "L" : "M") + (i * step).toFixed(1) + " " + (1.5 + (1 - v) * 15).toFixed(1)).join(" ");
    svg.innerHTML =
      `<defs><linearGradient id="tray-g-${key}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity=".22"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></linearGradient></defs>` +
      `<path d="M0 18 ${line.replace(/^M/, "L")} L70 18 Z" fill="url(#tray-g-${key})"/>` +
      `<path d="${line}" fill="none" stroke="${color}" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>`;
  }

  function tickMetrics() {
    for (const key in metrics) {
      const m = metrics[key];
      m.value = Math.min(m.max, Math.max(m.min, m.value + (Math.random() - 0.5) * m.step * 2));
      m.history.push(m.value);
      m.history.shift();
      renderMetricText(key);
    }
    if (state.tab === "clean" && state.screen === "welcome") sparks.forEach((s) => s.draw());
    renderTrayMetrics();
  }

  setInterval(() => {
    if (!reduced && state.inView && !document.hidden) tickMetrics();
  }, 1000);

  /* ---------- history chart & lifetime ---------- */
  const histPlot = $("mk-hist-plot");
  const histSel = $("hist-sel");

  function niceStep(raw) {
    const p = Math.pow(10, Math.floor(Math.log10(raw)));
    const n = raw / p;
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
  }

  function renderHistory() {
    histSel.textContent = "";
    if (!state.history.length) {
      const ghosts = [0.35, 0.6, 0.45, 0.8, 0.5, 0.7, 0.4, 0.55].map((h) => `<span style="height:${90 * h}px"></span>`).join("");
      histPlot.innerHTML = `<div class="mk-ghost-bars">${ghosts}</div><div class="mk-empty-msg"><b>No cleanups yet</b><span>Each cleanup you run will appear here.</span></div>`;
      return;
    }
    const bars = state.history.slice(0, 8).reverse();
    const max = Math.max(...bars.map((b) => b.gb));
    const step = niceStep(max / 2);
    const top = Math.ceil(max / step) * step;
    const ticks = [];
    for (let v = 0; v <= top + 1e-9; v += step) ticks.push(v);
    const tickLabel = (gb) => (gb === 0 ? "0 MB" : gb < 1 ? Math.round(gb * 1000) + " MB" : Number(gb.toFixed(1)) + " GB");

    histPlot.innerHTML =
      `<div class="mk-chart"><div class="mk-chart-y">${ticks.map((t) => `<span style="bottom:${(t / top) * 100}%">${tickLabel(t)}</span>`).join("")}</div>` +
      `<div class="mk-chart-area">${ticks.slice(1).map((t) => `<div class="mk-grid-line" style="bottom:${(t / top) * 100}%"></div>`).join("")}` +
      `<div class="mk-bars">${Array.from({ length: 8 }, (_, i) => {
        const b = bars[i];
        if (!b) return `<div></div>`;
        return `<div class="mk-bar-slot" data-i="${i}"><span class="mk-bar-tip" style="bottom:${(b.gb / top) * 100}%">${fmt(b.gb)}</span><div class="mk-bar" data-h="${(b.gb / top) * 100}" style="height:0"></div></div>`;
      }).join("")}</div></div>` +
      `<div class="mk-chart-x">${Array.from({ length: 8 }, (_, i) => `<span>${bars[i] ? "Today" : ""}</span>`).join("")}</div></div>`;

    const barsEl = histPlot.querySelector(".mk-bars");
    histPlot.querySelectorAll(".mk-bar-slot").forEach((slot) => {
      const b = bars[+slot.dataset.i];
      slot.addEventListener("pointerenter", () => {
        slot.classList.add("sel");
        barsEl.classList.add("has-sel");
        histSel.textContent = `Today · ${fmt(b.gb)}`;
      });
      slot.addEventListener("pointerleave", () => {
        slot.classList.remove("sel");
        barsEl.classList.remove("has-sel");
        histSel.textContent = "";
      });
    });
    requestAnimationFrame(() =>
      requestAnimationFrame(() => histPlot.querySelectorAll(".mk-bar").forEach((bar) => (bar.style.height = bar.dataset.h + "%")))
    );
  }

  const rtf = "Intl" in window && Intl.RelativeTimeFormat ? new Intl.RelativeTimeFormat("en", { numeric: "auto" }) : null;
  function relative(date) {
    const s = Math.round((date - Date.now()) / 1000);
    if (s > -60) return "Just now";
    if (!rtf) return "Earlier";
    if (s > -3600) return rtf.format(Math.round(s / 60), "minute");
    return rtf.format(Math.round(s / 3600), "hour");
  }

  function renderTotals() {
    $("lifetime-total").textContent = fmt(state.totalCleanedGB);
    $("lifetime-runs").textContent = state.history.length;
    $("lifetime-last").textContent = state.history.length ? relative(state.history[0].date) : "Never";
  }
  setInterval(() => state.history.length && renderTotals(), 30000);

  /* ---------- scan permission sheet & scanning ---------- */
  const modal = $("scan-permission-modal");
  let scanTimer = null;

  function openSheet(el) {
    el.classList.add("open");
    el.setAttribute("aria-hidden", "false");
  }
  function closeSheet(el) {
    el.classList.remove("open");
    el.setAttribute("aria-hidden", "true");
  }

  function requestScan() {
    if (state.screen === "scanning" || state.screen === "cleaning") {
      setTab("clean");
      return;
    }
    if (!state.permissionGranted) {
      setScreen("welcome");
      openSheet(modal);
      return;
    }
    startScan();
  }

  $("btn-start-scan").addEventListener("click", requestScan);
  $("btn-modal-cancel").addEventListener("click", () => closeSheet(modal));
  $("btn-modal-confirm").addEventListener("click", () => {
    state.permissionGranted = true;
    closeSheet(modal);
    startScan();
  });

  function startScan() {
    clearInterval(scanTimer);
    state.results = null;
    renderDisk();
    let progress = 0;
    let files = 0;
    let tick = 0;
    const pctEl = $("scan-counter-pct");
    const fill = $("scan-progress-fill");
    const filesEl = $("scan-files-inspected");
    const pathEl = $("scan-path-text");
    const paint = () => {
      pctEl.textContent = Math.round(progress * 100) + "%";
      fill.style.width = progress * 100 + "%";
      filesEl.textContent = files.toLocaleString("en-US") + " files inspected";
    };
    pathEl.textContent = SCAN_PATHS[0];
    paint();
    setScreen("scanning");

    scanTimer = setInterval(() => {
      tick++;
      progress = Math.min(1, progress + 0.014 + Math.random() * 0.02);
      files += 900 + Math.floor(Math.random() * 2600);
      if (tick % 3 === 0) pathEl.textContent = SCAN_PATHS[(tick / 3) % SCAN_PATHS.length];
      paint();
      renderTray();
      if (progress >= 1) {
        clearInterval(scanTimer);
        setTimeout(finishScan, 450);
      }
    }, 90);
  }

  function finishScan() {
    if (state.screen !== "scanning") return;
    const factor = state.history.length ? 0.12 + Math.random() * 0.18 : 1;
    state.results = CATEGORIES.map((c, i) => ({ ...c, gb: round2(Math.max(0.05, c.gb * factor)), index: i, selected: true }));
    renderDisk();
    renderTriage();
    setScreen("triage");
  }

  $("btn-cancel-scan").addEventListener("click", () => {
    clearInterval(scanTimer);
    setScreen("welcome");
  });

  /* ---------- review cleanup ---------- */
  const triageList = $("triage-items-list");
  const finderIcon =
    '<svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><rect x="1.5" y="1.5" width="13" height="13" rx="3"/><path d="M6.5 9.5 10.8 5.2M7.2 5.2h3.6v3.6"/></svg>';

  function renderTriage() {
    if (!state.results) return;
    const rows = state.results.slice().sort((a, b) => (state.sort === "size" ? b.gb - a.gb : a.name.localeCompare(b.name)));
    triageList.innerHTML = rows
      .map(
        (r) => `<div class="mk-row${r.selected ? "" : " off"}" data-id="${r.id}">
          <input type="checkbox" class="mk-check" ${r.selected ? "checked" : ""} aria-label="Include ${esc(r.name)}">
          <span class="mk-cat-bar" style="background:${CATEGORY_COLORS[r.index % CATEGORY_COLORS.length]}"></span>
          <div class="mk-row-info"><div class="mk-row-name">${esc(r.name)}</div><div class="mk-row-path">${esc(r.path)}</div></div>
          <div class="mk-row-size">${fmt(r.gb)}</div>
          <button class="mk-finder" title="Show in Finder" aria-label="Show ${esc(r.name)} in Finder">${finderIcon}</button>
        </div>`
      )
      .join("");
    $("triage-sub").textContent = `${state.results.length} safe areas found. Choose what to remove.`;
    updateTriageTotals();
  }

  function updateTriageTotals() {
    const sel = selectedItems();
    const total = selectedGB();
    $("triage-selected-count").textContent = `${sel.length} of ${state.results.length} selected`;
    $("triage-selected-total").textContent = fmt(total);
    const btn = $("btn-execute-clean");
    btn.textContent = `Clean ${fmt(total)}`;
    btn.disabled = sel.length === 0;
    $("btn-select-all").textContent = sel.length ? "Deselect All" : "Select All";
    triageList.querySelectorAll(".mk-row").forEach((row) => {
      const item = state.results.find((r) => r.id === row.dataset.id);
      row.classList.toggle("off", !item.selected);
      row.querySelector(".mk-check").checked = item.selected;
    });
    renderTray();
  }

  triageList.addEventListener("click", (e) => {
    if (e.target.closest(".mk-finder")) return; // Show in Finder: no-op on the website
    const row = e.target.closest(".mk-row");
    if (!row || !state.results) return;
    const item = state.results.find((r) => r.id === row.dataset.id);
    item.selected = e.target.classList.contains("mk-check") ? e.target.checked : !item.selected;
    updateTriageTotals();
  });

  $("btn-select-all").addEventListener("click", () => {
    if (!state.results) return;
    const any = selectedItems().length > 0;
    state.results.forEach((r) => (r.selected = !any));
    updateTriageTotals();
  });

  win.querySelectorAll(".mk-sortseg .mk-seg-btn").forEach((b) =>
    b.addEventListener("click", () => {
      state.sort = b.dataset.sort;
      win.querySelectorAll(".mk-sortseg .mk-seg-btn").forEach((x) => x.classList.toggle("active", x === b));
      renderTriage();
    })
  );

  $("btn-triage-back").addEventListener("click", () => setScreen("welcome"));

  /* ---------- cleaning & summary ---------- */
  let cleanTimer = null;
  const checkIcon =
    '<svg width="14" height="14" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7.5" fill="currentColor"/><path d="m4.8 8.2 2.1 2.1 4.3-4.5" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  function startClean() {
    const items = selectedItems().slice().sort((a, b) => b.gb - a.gb);
    if (!items.length) return;
    clearInterval(cleanTimer);
    const log = $("mk-clean-log");
    const pctEl = $("cleaning-pct-num");
    const fill = $("cleaning-progress-fill");
    const phase = $("cleaning-phase-label");
    log.innerHTML = '<div class="mk-clean-empty">Preparing…</div>';
    pctEl.textContent = "0%";
    fill.style.width = "0%";
    phase.textContent = "Preparing…";
    setScreen("cleaning");

    let i = 0;
    let progress = 0;
    const stepsPer = 5;
    let sub = 0;
    cleanTimer = setInterval(() => {
      const item = items[i];
      phase.textContent = `Removing ${item.name}…`;
      sub++;
      progress = (i + sub / stepsPer) / items.length;
      pctEl.textContent = Math.round(progress * 100) + "%";
      fill.style.width = progress * 100 + "%";
      renderTray();
      if (sub >= stepsPer) {
        if (i === 0) log.textContent = "";
        const row = document.createElement("div");
        row.className = "mk-log-row";
        row.innerHTML = `${checkIcon}<span>${esc(item.name)}</span><b>${fmt(item.gb)}</b>`;
        log.appendChild(row);
        sub = 0;
        i++;
        if (i >= items.length) {
          clearInterval(cleanTimer);
          phase.textContent = "Finishing up…";
          setTimeout(() => finishClean(items), 600);
        }
      }
    }, 110);
  }

  function finishClean(items) {
    const gb = round2(items.reduce((s, r) => s + r.gb, 0));
    state.usedGB = round2(state.usedGB - gb);
    state.totalCleanedGB = round2(state.totalCleanedGB + gb);
    state.history.unshift({ gb, date: Date.now(), count: items.length });
    state.results = null;

    $("summary-big").textContent = `${fmt(gb)} reclaimed`;
    $("summary-sub").textContent = `${items.length} ${items.length === 1 ? "area" : "areas"} cleaned on Macintosh HD`;
    const max = Math.max(...items.map((r) => r.gb));
    const bd = $("mk-breakdown");
    bd.innerHTML = items
      .map(
        (r) => `<div class="mk-bd-row"><span class="mk-bd-name">${esc(r.name)}</span><span class="mk-bd-track"><span data-w="${Math.max(2, (r.gb / max) * 100)}" style="background:${CATEGORY_COLORS[r.index % CATEGORY_COLORS.length]}"></span></span><span class="mk-bd-size">${fmt(r.gb)}</span></div>`
      )
      .join("");
    renderDisk();
    renderTotals();
    setScreen("summary");
    bd.querySelectorAll(".mk-bd-track span").forEach((s, idx) =>
      setTimeout(() => (s.style.width = s.dataset.w + "%"), 60 + idx * 50)
    );
  }

  $("btn-execute-clean").addEventListener("click", startClean);
  $("btn-summary-done").addEventListener("click", () => setScreen("welcome"));

  /* ---------- apps ---------- */
  let apps = [
    { name: "Arc", colors: ["#FF5F6D", "#7C3AED"] },
    { name: "Docker", colors: ["#38BDF8", "#2563EB"] },
    { name: "Figma", colors: ["#F97316", "#A855F7"] },
    { name: "Notion", colors: ["#3F3F46", "#111319"] },
    { name: "Slack", colors: ["#E01E5A", "#4A154B"] },
    { name: "Spotify", colors: ["#22C55E", "#15803D"] },
    { name: "Visual Studio Code", colors: ["#3B9EFF", "#0065A9"] },
    { name: "Xcode", colors: ["#60A5FA", "#1D4ED8"] },
  ].map((a) => ({ ...a, path: `/Applications/${a.name}.app` }));
  const appsList = $("mk-apps-list");
  const appsSearch = $("apps-search");
  const alertEl = $("mk-alert");
  let pendingUninstall = null;

  function renderApps() {
    const q = appsSearch.value.trim().toLowerCase();
    const list = q ? apps.filter((a) => a.name.toLowerCase().includes(q)) : apps;
    $("apps-sub").textContent = `${apps.length} apps installed. Uninstalled apps go to the Trash.`;
    if (!list.length) {
      appsList.innerHTML = `<div class="mk-apps-empty"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="7.5" height="7.5" rx="1.5"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="1.5"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="1.5"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.5"/></svg><b>${
        q ? `No results for “${esc(appsSearch.value.trim())}”` : "No applications found"
      }</b></div>`;
      return;
    }
    appsList.innerHTML = list
      .map(
        (a) => `<div class="mk-app-row" data-name="${esc(a.name)}">
          <span class="mk-app-icon" style="background:linear-gradient(145deg, ${a.colors[0]}, ${a.colors[1]})">${esc(a.name.charAt(0))}</span>
          <div class="mk-app-info"><div class="mk-app-name">${esc(a.name)}</div><div class="mk-app-path">${esc(a.path)}</div></div>
          <div class="mk-app-actions"><button class="mk-btn-ghost" data-act="finder">Show in Finder</button><button class="mk-uninstall" data-act="uninstall">Uninstall</button></div>
        </div>`
      )
      .join("");
  }

  appsSearch.addEventListener("input", renderApps);
  appsList.addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-act]");
    if (!btn || btn.dataset.act !== "uninstall") return;
    pendingUninstall = btn.closest(".mk-app-row").dataset.name;
    $("mk-alert-title").textContent = `Move ${pendingUninstall} to Trash?`;
    openSheet(alertEl);
  });
  $("mk-alert-cancel").addEventListener("click", () => closeSheet(alertEl));
  $("mk-alert-confirm").addEventListener("click", () => {
    apps = apps.filter((a) => a.name !== pendingUninstall);
    closeSheet(alertEl);
    renderApps();
  });

  /* ---------- menu bar popover ---------- */
  const trayBtn = $("tray-toggle-btn");
  const tray = $("tray-popover");

  function renderTrayMetrics() {
    if (!tray.classList.contains("open")) return;
    drawTraySpark($("tray-spark-cpu"), "cpu");
    drawTraySpark($("tray-spark-mem"), "mem");
    $("tray-cpu-val").textContent = Math.round(metrics.cpu.value * 100) + "%";
    $("tray-mem-val").textContent = Math.round(metrics.mem.value * 100) + "% used";
  }

  function renderTray() {
    const r = usedRatio();
    const tone = diskTone(r);
    const pct = Math.round(r * 100);
    const arc = $("tray-ring-arc");
    arc.setAttribute("stroke-dasharray", `${pct} 100`);
    arc.style.stroke = tone.ui;
    $("tray-ring-pct").textContent = pct + "%";
    $("tray-free").textContent = fmt(freeGB());
    $("tray-used").textContent = `${fmt(state.usedGB)} of ${fmt(TOTAL_GB)} used`;

    let status = tone.tray;
    let dot = tone.ui === C.accent ? C.success : tone.ui;
    let label = "Scan My Mac";
    if (state.screen === "scanning") {
      status = "Scanning";
      dot = C.accent;
      label = `Scanning… ${$("scan-counter-pct").textContent}`;
    } else if (state.screen === "cleaning") {
      status = "Cleaning";
      dot = C.accent;
      label = `Cleaning… ${$("cleaning-pct-num").textContent}`;
    } else if (state.results && selectedItems().length) {
      label = `Review ${fmt(selectedGB())} to clean`;
    }
    $("tray-status-text").textContent = status;
    $("tray-status-dot").style.background = dot;
    $("tray-scan-label").textContent = label;
    renderTrayMetrics();
  }

  function setTray(open) {
    tray.classList.toggle("open", open);
    trayBtn.classList.toggle("active", open);
    trayBtn.setAttribute("aria-expanded", open ? "true" : "false");
    if (open) renderTray();
  }

  trayBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    setTray(!tray.classList.contains("open"));
  });
  document.addEventListener("click", (e) => {
    if (tray.classList.contains("open") && !tray.contains(e.target) && !trayBtn.contains(e.target)) setTray(false);
  });
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    setTray(false);
    closeSheet(modal);
    closeSheet(alertEl);
  });
  $("tray-scan-action").addEventListener("click", () => {
    setTray(false);
    if (state.results && state.screen !== "scanning" && state.screen !== "cleaning") setScreen("triage");
    else requestScan();
  });
  $("tray-open-window").addEventListener("click", () => {
    setTray(false);
    setTab("clean");
  });
  $("tray-about").addEventListener("click", () => setTray(false));
  $("tray-quit").addEventListener("click", () => setTray(false));

  /* ---------- reduced motion ---------- */
  const onMotionChange = (e) => {
    reduced = e.matches;
    state.heroPaused = reduced;
    if (reduced) hero.dispatchEvent(new Event("pointerleave"));
    updateVideos();
  };
  if (motionQuery.addEventListener) motionQuery.addEventListener("change", onMotionChange);
  else if (motionQuery.addListener) motionQuery.addListener(onMotionChange);

  /* ---------- initial render ---------- */
  renderDisk();
  renderTotals();
  renderApps();
  showActive();
}

document.addEventListener("DOMContentLoaded", () => {
  initAppDemo();

  // 7. FAQ Accordion
  const faqBtns = document.querySelectorAll(".faq-btn");
  faqBtns.forEach(btn => {
    btn.addEventListener("click", () => {
      const body = btn.nextElementSibling;
      const icon = btn.querySelector(".faq-icon");
      const isOpen = body.classList.contains("open");

      document.querySelectorAll(".faq-body").forEach(b => b.classList.remove("open"));
      document.querySelectorAll(".faq-icon").forEach(i => i.textContent = "↓");

      if (!isOpen) {
        body.classList.add("open");
        if (icon) icon.textContent = "↑";
      }
    });
  });

  // 8. Theme Switcher (Time-Aware Auto Theme + Manual Toggle with Persistence)
  const themeToggleBtn = document.getElementById("theme-toggle-btn");
  const mobileThemeToggleBtn = document.getElementById("mobile-theme-toggle-btn");
  const storedTheme = localStorage.getItem("mackitty-theme");

  function applyTheme(theme) {
    if (theme === "light") {
      document.documentElement.setAttribute("data-theme", "light");
    } else {
      document.documentElement.removeAttribute("data-theme");
    }
  }

  function getAutoTimeTheme() {
    // Local user time: Morning/Day (06:00 to 18:00) = light mode; Night (18:00 to 06:00) = dark mode
    const hour = new Date().getHours();
    return (hour >= 6 && hour < 18) ? "light" : "dark";
  }

  if (storedTheme) {
    applyTheme(storedTheme);
  } else {
    // If no manual preference set, use user's local day/night schedule
    applyTheme(getAutoTimeTheme());
  }

  function toggleCurrentTheme() {
    const currentTheme = document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
    const nextTheme = (currentTheme === "light") ? "dark" : "light";
    applyTheme(nextTheme);
    localStorage.setItem("mackitty-theme", nextTheme);
  }

  if (themeToggleBtn) {
    themeToggleBtn.addEventListener("click", toggleCurrentTheme);
  }
  if (mobileThemeToggleBtn) {
    mobileThemeToggleBtn.addEventListener("click", toggleCurrentTheme);
  }

  // 9. Mobile Navigation Drawer
  const mobileNavToggle = document.getElementById("btn-mobile-nav-toggle");
  const mobileNavDrawer = document.getElementById("mobile-nav-drawer");
  const mobileNavBackdrop = document.getElementById("mobile-nav-backdrop");

  function closeMobileNav() {
    if (mobileNavDrawer) mobileNavDrawer.classList.remove("open");
    if (mobileNavToggle) {
      mobileNavToggle.classList.remove("active");
      mobileNavToggle.setAttribute("aria-expanded", "false");
    }
    document.body.style.overflow = "";
  }

  function openMobileNav() {
    if (mobileNavDrawer) mobileNavDrawer.classList.add("open");
    if (mobileNavToggle) {
      mobileNavToggle.classList.add("active");
      mobileNavToggle.setAttribute("aria-expanded", "true");
    }
    document.body.style.overflow = "hidden";
  }

  if (mobileNavToggle && mobileNavDrawer) {
    mobileNavToggle.addEventListener("click", (e) => {
      e.stopPropagation();
      const isOpen = mobileNavDrawer.classList.contains("open");
      if (isOpen) {
        closeMobileNav();
      } else {
        openMobileNav();
      }
    });

    if (mobileNavBackdrop) {
      mobileNavBackdrop.addEventListener("click", closeMobileNav);
    }

    // Close on navigation link tap
    const drawerLinks = mobileNavDrawer.querySelectorAll("a");
    drawerLinks.forEach(link => {
      link.addEventListener("click", () => {
        closeMobileNav();
      });
    });

    // Close on Escape key
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && mobileNavDrawer.classList.contains("open")) {
        closeMobileNav();
      }
    });
  }
});
