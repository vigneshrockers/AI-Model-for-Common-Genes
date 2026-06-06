# AI Model for Common Genes

Local web app for uploading multiple differential-expression Excel sheets, selecting which sheets to analyze, choosing the intersection/filter columns, calculating common genes, and generating an R volcano plot.

## Run

For normal local testing:

```powershell
python app.py
```

For production-style local running without Flask's development-server warning:

```powershell
pip install -r requirements.txt
python server.py
```

Open:

```text
http://127.0.0.1:5050
```

The app stores uploaded files in `data/uploads` and generated R plot PNG files in `data/plots`.

For deployment guidance, see `DEPLOYMENT.md`.
