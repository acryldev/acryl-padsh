/**
 * Pre-rendered ASCII splash marks.
 *
 * `ACRYL_LOGO` is the upstream Prime Agent mark (source:
 * assets/brand/prime-butterfly.svg; re-render at any width with
 * `uv run scripts/render-logo.py --width N`), kept for attribution/reference
 * — ACRYL is a fork of Prime Agent, not the same project.
 * `ACRYL_WORDMARK_LOGO` is this project's own splash mark: a 5x7
 * block-letter wordmark, built programmatically (5-column letter grids
 * joined with a single-space separator, verified 29 columns per row)
 * rather than hand-transcribed, to avoid ASCII-art alignment errors.
 */

/** ~10 rows × 32 cols. Upstream Prime Agent mark — half-block butterfly. */
export const ACRYL_LOGO = `                          ▄▄███▀
    ▄▄▄▄▄              ▄█████▀
    ██████▄         ▄██████▀
   ▄███▀███▄     ▄███▀▄██▀
   ███ ▄████▄▄▄████▀▄▄██
  ▀██  ▀█████████▀▀▀▀▀▀
  ▄██   ██████▀▀ ▄███
 █████    ▀█▄▄▄█████▀
███████▄  ████████▀
▀███▀▀    █████▀`;

/**
 * 7 rows × 29 cols. ACRYL's own splash mark — a block-letter wordmark,
 * built programmatically (5-column letter grids per character, joined and
 * length-verified in a throwaway script) rather than hand-transcribed, to
 * avoid ASCII-art alignment errors. No real ACRYL vector brand mark exists
 * yet; swap this for a from-scratch interpretation of one once it does,
 * the same way the AMIDE-era wordmark was later paired with a real SVG.
 */
export const ACRYL_WORDMARK_LOGO = ` ███   ████ ████  █   █ █    
█   █ █     █   █ █   █ █    
█   █ █     █   █  █ █  █    
█████ █     ████    █   █    
█   █ █     █ █     █   █    
█   █ █     █  █    █   █    
█   █  ████ █   █   █   █████`;
