# Deployment

## Why Vercel is not a good fit

This project is a Flask web app that stores uploaded Excel files and runs `Rscript` to generate volcano plots. Vercel is best for static frontends and serverless API functions. It is not a good fit here because:

- Uploaded files are stored on disk, but Vercel's serverless filesystem is not persistent.
- The app needs R installed so `volcano_plot.R` can run.
- Large Excel parsing and plot generation can exceed serverless runtime limits.

Use Render, Railway, Fly.io, Azure App Service, or another container-based host instead.

## Local production-style run

Install dependencies:

```powershell
pip install -r requirements.txt
```

Run with Waitress:

```powershell
python server.py
```

Open:

```text
http://127.0.0.1:5050
```

## Docker deployment

Build:

```powershell
docker build -t common-genes-ai .
```

Run:

```powershell
docker run -p 5050:5050 common-genes-ai
```

Deploy the same Dockerfile to a container host. The Dockerfile installs Python packages and `r-base`, so the R volcano plot can run in production.
