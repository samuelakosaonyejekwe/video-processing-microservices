const API = window.GATEWAY_URL || "/api";

const state = {
  token: localStorage.getItem("access_token") || "",
  email: localStorage.getItem("user_email") || "",
  jobId: "",
  filename: "",
  pollTimer: null,
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
};

function setAlert(message, type = "info") {
  els.alertBox.className = `alert ${type}`;
  els.alertBox.textContent = message;
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
  return {
    Authorization: `Bearer ${state.token}`,
    ...extra,
  };
}

async function apiFetch(path, options = {}) {
  const response = await fetch(`${API}${path}`, options);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail = body.detail || body.message || `Request failed (${response.status})`;
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
    state.token = data.access_token;
    state.email = email;
    localStorage.setItem("access_token", state.token);
    localStorage.setItem("user_email", state.email);
    showAuthenticatedView();
    resetConversionUi();
  } catch (error) {
    setAlert(error.message, "error");
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
    setAlert("Account created. Sign in to upload and convert videos.", "success");
  } catch (error) {
    setAlert(error.message, "error");
  }
}

function handleLogout() {
  localStorage.removeItem("access_token");
  localStorage.removeItem("user_email");
  state.token = "";
  state.email = "";
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
  if (!file || !state.token) return;

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
  if (!state.jobId || !state.token) return;

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
  if (state.token) {
    showAuthenticatedView();
    resetConversionUi();
  } else {
    showGuestView();
  }
}

init();
