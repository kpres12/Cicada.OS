# Cicada.OS website

Static GitHub Pages site. Aesthetic: MAGI / Sentry HUD (`docs/DESIGN.md`).
IA: GrapheneOS-shaped (Features · Download · Install · FAQ · Source).

## Local preview

```bash
cd site && python3 -m http.server 8080
# open http://127.0.0.1:8080
```

## Publish

1. Push `site/` to `main`
2. Repo → Settings → Pages → Source: **GitHub Actions**
3. Workflow: [`.github/workflows/pages.yml`](../.github/workflows/pages.yml)
4. URL: `https://kpres12.github.io/Cicada.OS/` (once Actions has run)

Attach ISO builds to GitHub Releases; the Download page links `releases/latest`.
