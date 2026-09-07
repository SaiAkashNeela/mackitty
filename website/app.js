/**
 * MacKitty — Native macOS App Interactive Simulator & Site Controller
 * Matches exact logic from SimpleDashboardView.swift & TrayMiniDashboardView.swift
 */

document.addEventListener("DOMContentLoaded", () => {
  // Elements
  const videoLayer = document.getElementById("mac-app-video");
  const catAura = document.getElementById("cat-aura");
  const catMask = document.getElementById("cat-mask");

  const statusDot = document.getElementById("window-status-dot");
  const statusLabel = document.getElementById("window-status-label");

  const screenWelcome = document.getElementById("screen-welcome");
  const screenScanning = document.getElementById("screen-scanning");
  const screenTriage = document.getElementById("screen-triage");
  const screenCleaning = document.getElementById("screen-cleaning");

  const scanModal = document.getElementById("scan-permission-modal");
  const btnStartScan = document.getElementById("btn-start-scan");
  const btnModalCancel = document.getElementById("btn-modal-cancel");
  const btnModalConfirm = document.getElementById("btn-modal-confirm");
  const btnCancelScan = document.getElementById("btn-cancel-scan");
  const btnTriageBack = document.getElementById("btn-triage-back");
  const btnExecuteClean = document.getElementById("btn-execute-clean");
  const btnSummaryDone = document.getElementById("btn-summary-done");

  const trayToggleBtn = document.getElementById("tray-toggle-btn");
  const trayPopover = document.getElementById("tray-popover");
  const trayScanAction = document.getElementById("tray-scan-action");
  const trayCleanAction = document.getElementById("tray-clean-action");

  let scanInterval = null;
  let cleanInterval = null;

  // Set Screen State
  function setScreen(screenName) {
    // Hide all screens
    [screenWelcome, screenScanning, screenTriage, screenCleaning].forEach(s => {
      if (s) s.classList.remove("active");
    });

    // Update video flip and cat spotlight position (from SimpleDashboardView.swift)
    const isResultsScreen = (screenName === "triage" || screenName === "cleaning");
    if (isResultsScreen) {
      videoLayer.classList.add("flipped");
      catAura.classList.add("flipped");
      catMask.classList.add("flipped");
    } else {
      videoLayer.classList.remove("flipped");
      catAura.classList.remove("flipped");
      catMask.classList.remove("flipped");
    }

    // Update titlebar status
    statusDot.className = "status-dot " + (screenName === "welcome" ? "idle" : screenName);
    if (screenName === "welcome") {
      screenWelcome.classList.add("active");
      statusLabel.textContent = "Idle";
    } else if (screenName === "scanning") {
      screenScanning.classList.add("active");
      statusLabel.textContent = "Scanning…";
      runScanningSimulation();
    } else if (screenName === "triage") {
      screenTriage.classList.add("active");
      statusLabel.textContent = "Ready to Clean";
    } else if (screenName === "cleaning") {
      screenCleaning.classList.add("active");
      statusLabel.textContent = "Cleaning…";
      runCleaningSimulation();
    }
  }

  // 1. Scan Trigger & Permission Modal
  if (btnStartScan) {
    btnStartScan.addEventListener("click", () => {
      scanModal.classList.add("open");
    });
  }

  if (btnModalCancel) {
    btnModalCancel.addEventListener("click", () => {
      scanModal.classList.remove("open");
    });
  }

  if (btnModalConfirm) {
    btnModalConfirm.addEventListener("click", () => {
      scanModal.classList.remove("open");
      setScreen("scanning");
    });
  }

  // 2. Scanning Screen Simulation
  const scanCounterPct = document.getElementById("scan-counter-pct");
  const scanFilesInspected = document.getElementById("scan-files-inspected");
  const scanPathText = document.getElementById("scan-path-text");

  const scanPaths = [
    "~/Library/Developer/Xcode/DerivedData/Build/Products/Debug",
    "~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex",
    "~/Library/Caches/Homebrew/downloads/bottle_tarball.tar.gz",
    "~/.npm/_cacache/content-v2/sha512/04/8f",
    "~/Library/Caches/com.apple.dt.Xcode",
    "~/Library/Logs/DiagnosticReports/SimulatorAux.crash",
    "~/Downloads/Legacy_Install_Archive_v2.dmg"
  ];

  function runScanningSimulation() {
    clearInterval(scanInterval);
    let progress = 8;
    let files = 24500;
    let pathIdx = 0;

    scanInterval = setInterval(() => {
      progress += Math.floor(Math.random() * 9) + 4;
      files += Math.floor(Math.random() * 15000) + 8000;
      pathIdx = (pathIdx + 1) % scanPaths.length;

      if (progress >= 100) {
        progress = 100;
        clearInterval(scanInterval);
        scanCounterPct.textContent = "100%";
        scanFilesInspected.textContent = "184,310 files inspected";
        setTimeout(() => {
          setScreen("triage");
        }, 400);
      } else {
        scanCounterPct.textContent = progress + "%";
        scanFilesInspected.textContent = files.toLocaleString() + " files inspected";
        scanPathText.textContent = scanPaths[pathIdx];
      }
    }, 220);
  }

  if (btnCancelScan) {
    btnCancelScan.addEventListener("click", () => {
      clearInterval(scanInterval);
      setScreen("welcome");
    });
  }

  // 3. Triage Screen Logic & Dynamic Recalculation
  const triageCheckboxes = document.querySelectorAll(".triage-checkbox");
  const triageTotalText = document.getElementById("triage-selected-total");
  const triageCountText = document.getElementById("triage-selected-count");
  const btnSelectAll = document.getElementById("btn-select-all");

  function recalculateTriage() {
    let totalGB = 0;
    let checkedCount = 0;

    triageCheckboxes.forEach(cb => {
      const row = cb.closest(".triage-item-row");
      const sizeVal = parseFloat(row.getAttribute("data-size"));
      if (cb.checked) {
        totalGB += sizeVal;
        checkedCount++;
      }
    });

    const displaySize = totalGB > 0 ? totalGB.toFixed(2) + " GB" : "0 MB";
    if (triageTotalText) triageTotalText.textContent = displaySize;
    if (triageCountText) triageCountText.textContent = `${checkedCount} of ${triageCheckboxes.length} safe areas`;
    const kittyBadgeSpan = document.querySelector(".kitty-ready-badge span");
    if (kittyBadgeSpan) {
      kittyBadgeSpan.textContent = totalGB > 0 ? `✨ Kitty found ${displaySize} to save!` : `✨ No items selected`;
    }
    if (btnExecuteClean) {
      btnExecuteClean.textContent = `Clean Up — ${displaySize}`;
      btnExecuteClean.disabled = (checkedCount === 0);
      btnExecuteClean.style.opacity = (checkedCount === 0) ? "0.4" : "1";
    }
  }

  triageCheckboxes.forEach(cb => {
    cb.addEventListener("change", recalculateTriage);
    const row = cb.closest(".triage-item-row");
    row.addEventListener("click", (e) => {
      if (e.target !== cb) {
        cb.checked = !cb.checked;
        recalculateTriage();
      }
    });
  });

  if (btnSelectAll) {
    let allSelected = true;
    btnSelectAll.addEventListener("click", () => {
      allSelected = !allSelected;
      triageCheckboxes.forEach(cb => cb.checked = allSelected);
      btnSelectAll.textContent = allSelected ? "Clear All" : "Select All";
      recalculateTriage();
    });
  }

  if (btnTriageBack) {
    btnTriageBack.addEventListener("click", () => {
      setScreen("welcome");
    });
  }

  // 4. Cleaning Progress Screen
  const cleaningProgressArc = document.getElementById("cleaning-progress-arc");
  const cleaningPctNum = document.getElementById("cleaning-pct-num");
  const cleaningPhaseLabel = document.getElementById("cleaning-phase-label");
  const cleaningInProgressView = document.getElementById("cleaning-in-progress-view");
  const cleaningSuccessView = document.getElementById("cleaning-success-view");

  const cleanPhases = [
    "Flushing Xcode intermediate build caches…",
    "Purging Homebrew bottle download archives…",
    "Clearing unreferenced npm tarballs…",
    "Cleaning application logs & crash reports…",
    "Verifying filesystem integrity…"
  ];

  function runCleaningSimulation() {
    cleaningInProgressView.style.display = "block";
    cleaningSuccessView.classList.remove("show");
    let progress = 0;
    let phaseIdx = 0;

    clearInterval(cleanInterval);
    cleanInterval = setInterval(() => {
      progress += 10;
      phaseIdx = Math.min(cleanPhases.length - 1, Math.floor(progress / 22));

      // Circular arc offset calculation: circumference is ~415
      const offset = 415 - (415 * (progress / 100));
      if (cleaningProgressArc) cleaningProgressArc.style.strokeDashoffset = offset;
      if (cleaningPctNum) cleaningPctNum.textContent = progress + "%";
      if (cleaningPhaseLabel) cleaningPhaseLabel.textContent = cleanPhases[phaseIdx];

      if (progress >= 100) {
        clearInterval(cleanInterval);
        setTimeout(() => {
          cleaningInProgressView.style.display = "none";
          cleaningSuccessView.classList.add("show");
          statusDot.className = "status-dot cleaning";
          statusLabel.textContent = "Complete";

          // Update Disk Gauge on Welcome Screen to show newly reclaimed free space!
          updateDashboardPostClean();
        }, 500);
      }
    }, 180);
  }

  function updateDashboardPostClean() {
    const gaugeArc = document.getElementById("gauge-arc");
    const gaugeGlow = document.getElementById("gauge-glow");
    const gaugePctText = document.getElementById("gauge-pct-text");
    const diskDetailsText = document.getElementById("disk-details-text");
    const lifetimeVal = document.getElementById("lifetime-cleaned-val");

    if (gaugeArc && gaugeGlow && gaugePctText && diskDetailsText) {
      // 72% was 123 offset. 65% is 440 * (1 - 0.65) = 154 offset
      gaugeArc.style.strokeDashoffset = "154";
      gaugeGlow.style.strokeDashoffset = "154";
      gaugePctText.textContent = "65%";
      diskDetailsText.textContent = "333.7 GB of 512.0 GB used · 178.3 GB free";
      if (lifetimeVal) lifetimeVal.textContent = "83.08 GB";
    }
  }

  if (btnExecuteClean) {
    btnExecuteClean.addEventListener("click", () => {
      setScreen("cleaning");
    });
  }

  if (btnSummaryDone) {
    btnSummaryDone.addEventListener("click", () => {
      setScreen("welcome");
    });
  }

  // 5. Interactive Telemetry Cards (Mode Cycling)
  const cardCpu = document.getElementById("card-cpu");
  const valCpu = document.getElementById("val-cpu");
  let cpuMode = 0;
  const cpuStates = ["14% Load", "Apple M3 Max", "16 Cores"];
  if (cardCpu && valCpu) {
    cardCpu.addEventListener("click", () => {
      cpuMode = (cpuMode + 1) % cpuStates.length;
      valCpu.textContent = cpuStates[cpuMode];
    });
  }

  const cardGpu = document.getElementById("card-gpu");
  const valGpu = document.getElementById("val-gpu");
  let gpuMode = 0;
  const gpuStates = ["Metal 3", "36 GB Unified", "Active 18%"];
  if (cardGpu && valGpu) {
    cardGpu.addEventListener("click", () => {
      gpuMode = (gpuMode + 1) % gpuStates.length;
      valGpu.textContent = gpuStates[gpuMode];
    });
  }

  const cardMem = document.getElementById("card-mem");
  const valMem = document.getElementById("val-mem");
  let memMode = 0;
  const memStates = ["11.4 GB Used", "71% Used", "4.6 GB Free"];
  if (cardMem && valMem) {
    cardMem.addEventListener("click", () => {
      memMode = (memMode + 1) % memStates.length;
      valMem.textContent = memStates[memMode];
    });
  }

  const cardNet = document.getElementById("card-net");
  const valNet = document.getElementById("val-net");
  let netMode = 0;
  const netStates = ["Connected", "192.168.1.42"];
  if (cardNet && valNet) {
    cardNet.addEventListener("click", () => {
      netMode = (netMode + 1) % netStates.length;
      valNet.textContent = netStates[netMode];
    });
  }

  const cardBat = document.getElementById("card-bat");
  const valBat = document.getElementById("val-bat");
  let batMode = 0;
  const batStates = ["92% ⚡", "Power Adapter", "Health: 100%"];
  if (cardBat && valBat) {
    cardBat.addEventListener("click", () => {
      batMode = (batMode + 1) % batStates.length;
      valBat.textContent = batStates[batMode];
    });
  }

  // 6. Menu Bar Companion Dropdown Popover
  if (trayToggleBtn && trayPopover) {
    trayToggleBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      trayPopover.classList.toggle("open");
      trayToggleBtn.classList.toggle("active");
    });

    document.addEventListener("click", (e) => {
      if (!trayPopover.contains(e.target) && e.target !== trayToggleBtn) {
        trayPopover.classList.remove("open");
        trayToggleBtn.classList.remove("active");
      }
    });
  }

  if (trayScanAction) {
    trayScanAction.addEventListener("click", () => {
      trayPopover.classList.remove("open");
      trayToggleBtn.classList.remove("active");
      setScreen("scanning");
    });
  }

  if (trayCleanAction) {
    trayCleanAction.addEventListener("click", () => {
      trayPopover.classList.remove("open");
      trayToggleBtn.classList.remove("active");
      setScreen("triage");
    });
  }

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
