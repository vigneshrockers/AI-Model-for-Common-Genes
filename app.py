import json
import math
import shutil
import subprocess
import uuid
from itertools import combinations
from pathlib import Path

import pandas as pd
from flask import Flask, jsonify, render_template, request, send_from_directory
from werkzeug.utils import secure_filename


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
UPLOAD_DIR = DATA_DIR / "uploads"
PLOT_DIR = DATA_DIR / "plots"
R_SCRIPT = BASE_DIR / "volcano_plot.R"
ALLOWED_EXTENSIONS = {".xlsx", ".xls", ".csv", ".tsv"}

app = Flask(__name__)
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
PLOT_DIR.mkdir(parents=True, exist_ok=True)


def allowed_file(filename):
    return Path(filename).suffix.lower() in ALLOWED_EXTENSIONS


def manifest_path():
    return DATA_DIR / "manifest.json"


def load_manifest():
    path = manifest_path()
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8"))


def save_manifest(files):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    manifest_path().write_text(json.dumps(files, indent=2), encoding="utf-8")


def read_table(path):
    suffix = path.suffix.lower()
    if suffix in {".xlsx", ".xls"}:
        return pd.read_excel(path)
    if suffix == ".tsv":
        return pd.read_csv(path, sep="\t")
    return pd.read_csv(path)


def find_rscript():
    located = shutil.which("Rscript")
    if located:
        return located

    candidates = [
        Path(r"C:\Program Files\R"),
        Path(r"C:\Program Files (x86)\R"),
    ]
    for root in candidates:
        if not root.exists():
            continue
        matches = sorted(root.glob(r"R-*\bin\Rscript.exe"), reverse=True)
        matches.extend(sorted(root.glob(r"R-*\bin\x64\Rscript.exe"), reverse=True))
        if matches:
            return str(matches[0])
    return None


def numeric_series(df, column):
    return pd.to_numeric(df[column], errors="coerce")


def short_label(filename):
    lower = filename.lower()
    if "_ko" in lower or "-ko" in lower or " ko" in lower:
        return "KO"
    if "hetero" in lower or "het" in lower:
        return "Hetero"
    if "homo" in lower:
        return "Homo"
    return Path(filename).stem[:24]


def unique_label(base, used):
    label = base
    counter = 2
    while label in used:
        label = f"{base} {counter}"
        counter += 1
    used.add(label)
    return label


def common_metrics(filtered_sets, labels, filter_text, key_column):
    rows = [
        {"metric": "Filter", "value": filter_text},
        {"metric": "Intersection key", "value": key_column},
    ]

    all_keys = set().union(*filtered_sets.values()) if filtered_sets else set()
    for file_id, keys in filtered_sets.items():
        rows.append({"metric": f"{labels[file_id]} total", "value": len(keys)})

    if not filtered_sets:
        return rows

    selected_ids = list(filtered_sets.keys())
    for file_id in selected_ids:
        other_keys = set().union(
            *(filtered_sets[other_id] for other_id in selected_ids if other_id != file_id)
        ) if len(selected_ids) > 1 else set()
        rows.append(
            {
                "metric": f"{labels[file_id]} only",
                "value": len(filtered_sets[file_id] - other_keys),
            }
        )

    if len(selected_ids) >= 3:
        for pair in combinations(selected_ids, 2):
            others = [file_id for file_id in selected_ids if file_id not in pair]
            pair_common = filtered_sets[pair[0]].intersection(filtered_sets[pair[1]])
            other_union = set().union(*(filtered_sets[file_id] for file_id in others)) if others else set()
            rows.append(
                {
                    "metric": f"{labels[pair[0]]} and {labels[pair[1]]} only",
                    "value": len(pair_common - other_union),
                }
            )

    all_common = set.intersection(*(filtered_sets[file_id] for file_id in selected_ids))
    if len(selected_ids) == 3:
        rows.append({"metric": "All three", "value": len(all_common)})
    else:
        rows.append({"metric": "All selected", "value": len(all_common)})

    if len(selected_ids) >= 2:
        for pair in combinations(selected_ids, 2):
            pair_common = filtered_sets[pair[0]].intersection(filtered_sets[pair[1]])
            rows.append(
                {
                    "metric": f"{labels[pair[0]]} and {labels[pair[1]]} common total",
                    "value": len(pair_common),
                }
            )

    rows.append({"metric": "Union total", "value": len(all_keys)})
    return rows


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/api/files")
def files():
    return jsonify({"files": load_manifest()})


@app.post("/api/upload")
def upload():
    uploaded = request.files.getlist("files")
    if not uploaded:
        return jsonify({"error": "Upload at least one Excel, CSV, or TSV file."}), 400

    manifest = load_manifest()
    used_labels = {item["label"] for item in manifest}
    added = []

    for file in uploaded:
        if not file.filename or not allowed_file(file.filename):
            continue

        original = secure_filename(file.filename)
        file_id = uuid.uuid4().hex
        stored_name = f"{file_id}_{original}"
        saved_path = UPLOAD_DIR / stored_name
        file.save(saved_path)

        try:
            df = read_table(saved_path)
        except Exception as exc:
            saved_path.unlink(missing_ok=True)
            return jsonify({"error": f"Could not read {original}: {exc}"}), 400

        label = unique_label(short_label(original), used_labels)
        item = {
            "id": file_id,
            "filename": original,
            "storedName": stored_name,
            "label": label,
            "rows": int(len(df)),
            "columns": [str(col) for col in df.columns],
        }
        manifest.append(item)
        added.append(item)

    if not added:
        return jsonify({"error": "No supported files were uploaded."}), 400

    save_manifest(manifest)
    return jsonify({"files": manifest, "added": added})


@app.post("/api/analyze")
def analyze():
    payload = request.get_json(force=True)
    selected_ids = payload.get("fileIds", [])
    key_column = payload.get("keyColumn")
    fc_column = payload.get("fcColumn")
    p_column = payload.get("pColumn")
    fc_threshold = float(payload.get("fcThreshold", 2))
    p_threshold = float(payload.get("pThreshold", 0.05))

    if len(selected_ids) < 2:
        return jsonify({"error": "Select at least two uploaded sheets for common-gene analysis."}), 400

    manifest = {item["id"]: item for item in load_manifest()}
    missing_ids = [file_id for file_id in selected_ids if file_id not in manifest]
    if missing_ids:
        return jsonify({"error": "One or more selected files are no longer available."}), 400

    required = [key_column, fc_column, p_column]
    if not all(required):
        return jsonify({"error": "Choose an intersection key, logFC column, and p-value column."}), 400

    labels = {}
    filtered_sets = {}
    filtered_frames = {}
    plot_frames = []

    for file_id in selected_ids:
        item = manifest[file_id]
        labels[file_id] = item["label"]
        df = read_table(UPLOAD_DIR / item["storedName"])
        missing = [column for column in required if column not in df.columns]
        if missing:
            return jsonify({"error": f"{item['filename']} is missing columns: {', '.join(missing)}"}), 400

        work = df.copy()
        work["_key"] = work[key_column].astype(str).str.strip()
        work["_logfc"] = numeric_series(work, fc_column)
        work["_pvalue"] = numeric_series(work, p_column)
        work = work.dropna(subset=["_key", "_logfc", "_pvalue"])
        work = work[work["_key"] != ""]

        filtered = work[(work["_logfc"].abs() >= fc_threshold) & (work["_pvalue"] < p_threshold)].copy()
        filtered_sets[file_id] = set(filtered["_key"])
        filtered_frames[file_id] = filtered

        plot_piece = work[["_key", "_logfc", "_pvalue"]].copy()
        plot_piece["dataset"] = item["label"]
        plot_frames.append(plot_piece)

    common_keys = set.intersection(*(filtered_sets[file_id] for file_id in selected_ids))
    filter_text = f"{p_column} < {p_threshold:g} and |{fc_column}| >= {fc_threshold:g}"
    metrics = common_metrics(filtered_sets, labels, filter_text, key_column)

    common_rows = []
    for key in sorted(common_keys):
        row = {key_column: key}
        for file_id in selected_ids:
            match = filtered_frames[file_id][filtered_frames[file_id]["_key"] == key].iloc[0]
            row[f"{labels[file_id]} {fc_column}"] = round(float(match["_logfc"]), 4)
            row[f"{labels[file_id]} {p_column}"] = float(match["_pvalue"])
            if "external_gene_name" in match.index:
                row[f"{labels[file_id]} gene"] = str(match["external_gene_name"])
        common_rows.append(row)

    plot_url = None
    plot_status = "R plot was not generated."
    if plot_frames:
        plot_input = pd.concat(plot_frames, ignore_index=True)
        plot_input["is_common"] = plot_input["_key"].isin(common_keys)
        plot_id = uuid.uuid4().hex
        csv_path = PLOT_DIR / f"{plot_id}.csv"
        png_path = PLOT_DIR / f"{plot_id}.png"
        plot_input.to_csv(csv_path, index=False)

        rscript = find_rscript()
        if rscript:
            completed = subprocess.run(
                [
                    rscript,
                    str(R_SCRIPT),
                    str(csv_path),
                    str(png_path),
                    str(fc_threshold),
                    str(p_threshold),
                ],
                capture_output=True,
                text=True,
                timeout=90,
            )
            if completed.returncode == 0 and png_path.exists():
                plot_url = f"/plots/{png_path.name}"
                plot_status = "Volcano plot generated with R."
            else:
                plot_status = completed.stderr.strip() or "R did not return a plot image."
        else:
            plot_status = "Rscript was not found on this computer."

    return jsonify(
        {
            "metrics": metrics,
            "commonRows": common_rows[:500],
            "commonCount": len(common_rows),
            "plotUrl": plot_url,
            "plotStatus": plot_status,
        }
    )


@app.get("/plots/<path:filename>")
def plots(filename):
    return send_from_directory(PLOT_DIR, filename)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5050, debug=True)
