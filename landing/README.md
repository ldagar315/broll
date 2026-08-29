# Broll landing page

This is a small, static project page for the Broll Flutter app. It is intentionally kept in the same repository so the mobile prototype and its public-facing explanation can evolve together. The landing page uses the transparent logo variant at `assets/broll_logo_transparent.png`.

## Preview locally

From the repository root:

```text
python3 -m http.server 4173 --directory landing
```

Then open `http://localhost:4173`.

## Deploy on Vercel

Create a Vercel project from `ldagar315/broll` and set the project’s **Root Directory** to `landing`. Use the **Other** framework preset, leave the build command blank, and use `.` as the output directory. Vercel will serve `index.html` as a static site.

The GitHub buttons currently point to `https://github.com/ldagar315/broll`.
