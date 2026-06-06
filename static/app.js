const state = {
  files: [],
};

const preferred = {
  key: ["Feature_ID", "feature_id", "Gene", "gene", "external_gene_name"],
  fc: ["logFC", "LogFC", "log2FoldChange", "avg_log2FC"],
  p: ["adj.P.Val", "padj", "FDR", "P.Value", "pvalue", "p_val_adj"],
};

const els = {
  uploadForm: document.querySelector("#uploadForm"),
  fileInput: document.querySelector("#fileInput"),
  uploadStatus: document.querySelector("#uploadStatus"),
  fileList: document.querySelector("#fileList"),
  sheetCount: document.querySelector("#sheetCount"),
  keyColumn: document.querySelector("#keyColumn"),
  fcColumn: document.querySelector("#fcColumn"),
  pColumn: document.querySelector("#pColumn"),
  fcThreshold: document.querySelector("#fcThreshold"),
  pThreshold: document.querySelector("#pThreshold"),
  analyzeBtn: document.querySelector("#analyzeBtn"),
  metricBody: document.querySelector("#metricBody"),
  commonTable: document.querySelector("#commonTable"),
  resultStatus: document.querySelector("#resultStatus"),
  commonCount: document.querySelector("#commonCount"),
  plotImage: document.querySelector("#plotImage"),
  plotStatus: document.querySelector("#plotStatus"),
};

function allColumns() {
  return [...new Set(state.files.flatMap((file) => file.columns))];
}

function pickDefault(columns, candidates) {
  return candidates.find((candidate) => columns.includes(candidate)) || columns[0] || "";
}

function fillSelect(select, columns, value) {
  select.innerHTML = "";
  columns.forEach((column) => {
    const option = document.createElement("option");
    option.value = column;
    option.textContent = column;
    select.append(option);
  });
  select.value = value;
}

function selectedFileIds() {
  return [...document.querySelectorAll("[data-file-check]:checked")].map((input) => input.value);
}

function renderFiles() {
  els.fileList.innerHTML = "";
  state.files.forEach((file) => {
    const label = document.createElement("label");
    label.className = "file-row";
    label.innerHTML = `
      <input data-file-check type="checkbox" value="${file.id}" checked>
      <span>
        <strong>${file.label}</strong>
        <small>${file.filename} · ${file.rows.toLocaleString()} rows</small>
      </span>
    `;
    els.fileList.append(label);
  });
  updateSheetCount();

  const columns = allColumns();
  fillSelect(els.keyColumn, columns, pickDefault(columns, preferred.key));
  fillSelect(els.fcColumn, columns, pickDefault(columns, preferred.fc));
  fillSelect(els.pColumn, columns, pickDefault(columns, preferred.p));
}

function updateSheetCount() {
  const count = selectedFileIds().length;
  els.sheetCount.textContent = `${count} selected`;
}

function renderMetrics(rows) {
  els.metricBody.innerHTML = "";
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td>${row.metric}</td><td>${row.value}</td>`;
    els.metricBody.append(tr);
  });
}

function renderCommonTable(rows) {
  const thead = els.commonTable.querySelector("thead");
  const tbody = els.commonTable.querySelector("tbody");
  thead.innerHTML = "";
  tbody.innerHTML = "";

  if (!rows.length) {
    tbody.innerHTML = `<tr><td>No common genes found for the selected filters.</td></tr>`;
    return;
  }

  const columns = Object.keys(rows[0]);
  thead.innerHTML = `<tr>${columns.map((column) => `<th>${column}</th>`).join("")}</tr>`;
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    tr.innerHTML = columns.map((column) => `<td>${row[column] ?? ""}</td>`).join("");
    tbody.append(tr);
  });
}

async function loadFiles() {
  const response = await fetch("/api/files");
  const data = await response.json();
  state.files = data.files || [];
  renderFiles();
}

async function readJson(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return { error: text.includes("<!doctype") ? "Server returned an HTML error page. Check the deployment logs." : text };
  }
}

els.uploadForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const formData = new FormData();
  [...els.fileInput.files].forEach((file) => formData.append("files", file));
  els.uploadStatus.textContent = "Uploading...";

  const response = await fetch("/api/upload", { method: "POST", body: formData });
  const data = await readJson(response);
  if (!response.ok) {
    els.uploadStatus.textContent = data.error || "Upload failed";
    return;
  }

  state.files = data.files;
  els.uploadStatus.textContent = `${data.added.length} uploaded`;
  els.fileInput.value = "";
  renderFiles();
});

els.fileList.addEventListener("change", updateSheetCount);

els.analyzeBtn.addEventListener("click", async () => {
  els.resultStatus.textContent = "Analyzing...";
  els.plotStatus.textContent = "Preparing R plot...";

  const response = await fetch("/api/analyze", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      fileIds: selectedFileIds(),
      keyColumn: els.keyColumn.value,
      fcColumn: els.fcColumn.value,
      pColumn: els.pColumn.value,
      fcThreshold: Number(els.fcThreshold.value),
      pThreshold: Number(els.pThreshold.value),
    }),
  });
  const data = await readJson(response);

  if (!response.ok) {
    els.resultStatus.textContent = data.error || "Analysis failed";
    els.plotStatus.textContent = "Plot not generated";
    return;
  }

  renderMetrics(data.metrics);
  renderCommonTable(data.commonRows);
  els.resultStatus.textContent = "Analysis complete";
  els.commonCount.textContent = `${data.commonCount.toLocaleString()} genes`;
  els.plotStatus.textContent = data.plotStatus;
  if (data.plotUrl) {
    els.plotImage.src = `${data.plotUrl}?t=${Date.now()}`;
    els.plotImage.hidden = false;
  }
});

loadFiles();
