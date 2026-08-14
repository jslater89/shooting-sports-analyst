# Latent Log-Ratio Paper (Revised Structure)

Working revision of `../paper.tex`, reorganized so the theoretical core is separable from production hardening.

- **`paper-revised.tex`** — draft with an explicit stop line after the minimal model
- Bibliography: `\bibliography{../paper}` (uses `../paper.bib`)

Build from this directory, e.g.:

```bash
cd research/latent-log-ratio/revised
latexmk -pdf paper-revised.tex
```

Until this draft replaces the main paper, treat `../paper.tex` as the current reference writeup.