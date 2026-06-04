const API = window.GATEWAY_URL || "/api";
const WS_URL =
  window.NOTIFICATION_WS_URL ||
  `${window.location.protocol === "https:" ? "wss" : "ws"}://${window.location.host}/ws`;

const state = {
  email: "",
  jobId: "",
  filename: "",
  pollTimer: null,
  socket: null,
  authenticated: false,
};

const els = {
  authCard: document.getElementById("auth-card"),
  appCard: document.getElementById("app-card"),
  loginForm: document.getElementById("login-form"),
  registerForm: document.getElementById("register-form"),
  tabLogin: document.getElementById("tab-login"),
  tabRegister: document.getElementById("tab-register"),
  userEmail: document.getElementById("user-email"),
  logoutBtn: document.getElementById("logout-btn"),
  dropzone: document.getElementById("dropzone"),
  fileInput: document.getElementById("video-file"),
  fileMeta: document.getElementById("file-meta"),
  uploadBtn: document.getElementById("upload-btn"),
  downloadBtn: document.getElementById("download-btn"),
  alertBox: document.getElementById("alert-box"),
  progressBar: document.getElementById("progress-bar"),
  stepUpload: document.getElementById("step-upload"),
  stepProcess: document.getElementById("step-process"),
  stepDownload: document.getElementById("step-download"),
  authAlert: document.getElementById("auth-alert"),
};

function setAlert(message, type = "info") {
  els.alertBox.className = `alert ${type}`;
  els.alertBox.textContent = message;
}

// The main alert-box lives inside the (hidden) app card, so it is invisible
// during sign-in / registration. Auth feedback must use this alert, which sits
// inside the always-visible auth card.
function setAuthAlert(message, type = "error") {
  if (!els.authAlert) return;
  els.authAlert.className = `alert ${type}`;
  els.authAlert.textContent = message;
}

function clearAuthAlert() {
  if (!els.authAlert) return;
  els.authAlert.className = "alert error hidden";
  els.authAlert.textContent = "";
}

function setStep(step) {
  const steps = {
    upload: els.stepUpload,
    process: els.stepProcess,
    download: els.stepDownload,
  };
  Object.values(steps).forEach((node) => {
    node.classList.remove("active", "done");
  });

  if (step === "upload") {
    steps.upload.classList.add("active");
  } else if (step === "process") {
    steps.upload.classList.add("done");
    steps.process.classList.add("active");
  } else if (step === "download") {
    steps.upload.classList.add("done");
    steps.process.classList.add("done");
    steps.download.classList.add("active");
  }
}

function setProgress(value) {
  els.progressBar.style.width = `${Math.max(0, Math.min(value, 100))}%`;
}

function authHeaders(extra = {}) {
  return { ...extra };
}

function fetchOptions(options = {}) {
  return {
    credentials: "include",
    ...options,
    headers: {
      ...(options.headers || {}),
    },
  };
}

async function refreshAccessToken() {
  const response = await fetch(`${API}/auth/refresh`, fetchOptions({
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  }));

  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.detail || "Session expired. Please sign in again.");
  }
  return true;
}

async function apiFetch(path, options = {}, allowRefresh = true) {
  const response = await fetch(`${API}${path}`, fetchOptions(options));
  const body = await response.json().catch(() => ({}));

  // A 401 from the auth endpoints themselves is a real credential error
  // (e.g. wrong password) — do NOT try to refresh, or the user sees a
  // misleading "Session expired" instead of "Invalid credentials".
  const isAuthEndpoint =
    path.startsWith("/auth/login") ||
    path.startsWith("/auth/register") ||
    path.startsWith("/auth/refresh");

  if (response.status === 401 && allowRefresh && !isAuthEndpoint) {
    await refreshAccessToken();
    return apiFetch(path, options, false);
  }

  if (!response.ok) {
    // The gateway returns errors as {"error": {"message": "..."}}; also accept
    // {detail} / {message} for robustness.
    const detail =
      body.detail ||
      (body.error && body.error.message) ||
      body.message ||
      `Request failed (${response.status})`;
    throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
  }
  return body;
}

function showAuthenticatedView() {
  els.authCard.classList.add("hidden");
  els.appCard.classList.remove("hidden");
  els.userEmail.textContent = state.email || "Signed in";
}

function showGuestView() {
  els.authCard.classList.remove("hidden");
  els.appCard.classList.add("hidden");
}

function resetConversionUi() {
  clearInterval(state.pollTimer);
  state.jobId = "";
  state.filename = "";
  els.fileInput.value = "";
  els.fileMeta.textContent = "No file selected";
  els.uploadBtn.disabled = true;
  els.downloadBtn.classList.add("hidden");
  setProgress(0);
  setStep("upload");
  setAlert("Upload a video file to extract its audio track as MP3.", "info");
}

function switchTab(mode) {
  const isLogin = mode === "login";
  els.tabLogin.classList.toggle("active", isLogin);
  els.tabRegister.classList.toggle("active", !isLogin);
  els.loginForm.classList.toggle("hidden", !isLogin);
  els.registerForm.classList.toggle("hidden", isLogin);
  clearAuthAlert();
}

async function handleLogin(event) {
  event.preventDefault();
  const email = document.getElementById("login-email").value.trim();
  const password = document.getElementById("login-password").value;
  try {
    const data = await apiFetch("/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    state.email = data.email || email;
    state.authenticated = true;
    clearAuthAlert();
    showAuthenticatedView();
    resetConversionUi();
  } catch (error) {
    setAuthAlert(error.message, "error");
  }
}

async function handleRegister(event) {
  event.preventDefault();
  const username = document.getElementById("register-username").value.trim();
  const email = document.getElementById("register-email").value.trim();
  const password = document.getElementById("register-password").value;
  try {
    await apiFetch("/auth/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, email, password }),
    });
    switchTab("login");
    document.getElementById("login-email").value = email;
    setAuthAlert("Account created. Sign in to upload and convert videos.", "success");
  } catch (error) {
    setAuthAlert(error.message, "error");
  }
}

async function handleLogout() {
  try {
    await apiFetch("/auth/logout", {
      method: "POST",
    });
  } catch (error) {
    // Ignore logout errors and clear local session anyway.
  }

  state.email = "";
  state.authenticated = false;
  disconnectWebSocket();
  showGuestView();
  switchTab("login");
}

function handleFileSelection(file) {
  if (!file) {
    els.fileMeta.textContent = "No file selected";
    els.uploadBtn.disabled = true;
    return;
  }
  if (!file.type.startsWith("video/")) {
    setAlert("Please choose a valid video file.", "error");
    return;
  }
  state.filename = file.name;
  const sizeMb = (file.size / (1024 * 1024)).toFixed(2);
  els.fileMeta.textContent = `${file.name} (${sizeMb} MB)`;
  els.uploadBtn.disabled = false;
}

async function pollJobStatus() {
  if (!state.jobId) return;

  try {
    const status = await apiFetch(`/jobs/${state.jobId}/status`, {
      headers: authHeaders(),
    });

    if (status.status === "completed") {
      clearInterval(state.pollTimer);
      setProgress(100);
      setStep("download");
      els.downloadBtn.classList.remove("hidden");
      els.uploadBtn.disabled = false;
      setAlert("Conversion complete. Download your MP3 below.", "success");
      return;
    }

    if (status.status === "failed") {
      clearInterval(state.pollTimer);
      setStep("upload");
      setProgress(0);
      els.uploadBtn.disabled = false;
      const reason = status.error_message || "Conversion failed.";
      setAlert(reason, "error");
      return;
    }

    setAlert("Converting video to audio. This usually takes under a minute.", "info");
  } catch (error) {
    clearInterval(state.pollTimer);
    els.uploadBtn.disabled = false;
    setAlert(error.message, "error");
  }
}

async function handleUpload() {
  const file = els.fileInput.files[0];
  if (!file || !state.authenticated) return;

  const formData = new FormData();
  formData.append("file", file);

  els.uploadBtn.disabled = true;
  els.downloadBtn.classList.add("hidden");
  setStep("process");
  setProgress(20);
  setAlert("Uploading video...", "info");

  try {
    const result = await apiFetch("/upload", {
      method: "POST",
      headers: authHeaders(),
      body: formData,
    });

    state.jobId = result.job_id;
    setProgress(45);
    setAlert("Upload complete. Processing your video...", "info");
    connectWebSocket();

    clearInterval(state.pollTimer);
    state.pollTimer = setInterval(pollJobStatus, 3000);
    await pollJobStatus();
  } catch (error) {
    setStep("upload");
    setProgress(0);
    els.uploadBtn.disabled = false;
    setAlert(error.message, "error");
  }
}

async function handleDownload() {
  if (!state.jobId || !state.authenticated) return;

  try {
    const query = state.filename ? `?filename=${encodeURIComponent(state.filename)}` : "";
    const result = await apiFetch(`/jobs/${state.jobId}/download${query}`, {
      headers: authHeaders(),
    });
    window.location.href = result.download_url;
  } catch (error) {
    setAlert(error.message, "error");
  }
}

function connectWebSocket() {
  if (!WS_URL || state.socket) {
    return;
  }

  try {
    state.socket = new WebSocket(WS_URL);
    state.socket.onmessage = (event) => {
      const payload = JSON.parse(event.data);
      if (
        payload.type === "notification_sent" &&
        state.jobId &&
        payload.correlation_id
      ) {
        setAlert("Email notification sent for your conversion.", "success");
      }
    };
    state.socket.onclose = () => {
      state.socket = null;
    };
  } catch (error) {
    // WebSocket is optional; polling remains the source of truth.
  }
}

function disconnectWebSocket() {
  if (state.socket) {
    state.socket.close();
    state.socket = null;
  }
}

function bindEvents() {
  els.tabLogin.addEventListener("click", () => switchTab("login"));
  els.tabRegister.addEventListener("click", () => switchTab("register"));
  els.loginForm.addEventListener("submit", handleLogin);
  els.registerForm.addEventListener("submit", handleRegister);
  els.logoutBtn.addEventListener("click", handleLogout);
  els.uploadBtn.addEventListener("click", handleUpload);
  els.downloadBtn.addEventListener("click", handleDownload);

  els.dropzone.addEventListener("click", () => els.fileInput.click());
  els.fileInput.addEventListener("change", (event) => {
    handleFileSelection(event.target.files[0]);
  });

  ["dragenter", "dragover"].forEach((name) => {
    els.dropzone.addEventListener(name, (event) => {
      event.preventDefault();
      els.dropzone.classList.add("dragover");
    });
  });

  ["dragleave", "drop"].forEach((name) => {
    els.dropzone.addEventListener(name, (event) => {
      event.preventDefault();
      els.dropzone.classList.remove("dragover");
      if (name === "drop" && event.dataTransfer.files.length) {
        els.fileInput.files = event.dataTransfer.files;
        handleFileSelection(event.dataTransfer.files[0]);
      }
    });
  });
}

function init() {
  bindEvents();
  switchTab("login");
  restoreSession();
}

async function restoreSession() {
  try {
    const data = await apiFetch("/auth/session");
    state.email = data.email || "";
    state.authenticated = true;
    showAuthenticatedView();
    resetConversionUi();
  } catch (error) {
    showGuestView();
  }
}

init();
