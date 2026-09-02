# Sidebar Design QA

- Source visual truth: `/var/folders/0h/k8nffn9j7j334rfb7hy768c80000gn/T/TemporaryItems/NSIRD_screencaptureui_4GlyBZ/Screenshot 2026-09-01 at 16.14.50.png`
- Additional toolbar references: `/var/folders/0h/k8nffn9j7j334rfb7hy768c80000gn/T/TemporaryItems/NSIRD_screencaptureui_AH4R1K/Screenshot 2026-09-01 at 16.34.33.png` and `/var/folders/0h/k8nffn9j7j334rfb7hy768c80000gn/T/TemporaryItems/NSIRD_screencaptureui_X2NiLD/Screenshot 2026-09-01 at 16.34.49.png`
- Implementation screenshot: `/var/folders/0h/k8nffn9j7j334rfb7hy768c80000gn/T/com.openai.sky.CUAService/SubForge Screenshot 2026-09-01 at 4.53.25 PM.jpeg`
- Shortcut guide implementation screenshot: `/var/folders/0h/k8nffn9j7j334rfb7hy768c80000gn/T/com.openai.sky.CUAService/SubForge Screenshot 2026-09-01 at 5.01.07 PM.jpeg`
- Shortcut guide focus-state screenshot: `/var/folders/0h/k8nffn9j7j334rfb7hy768c800gn/T/com.openai.sky.CUAService/SubForge Screenshot 2026-09-01 at 5.07.45 PM.jpeg`
- Normalized comparison: `/tmp/SubForge-design-comparison.png`
- Viewport: native macOS window, `1226 × 768 px`; right inspector uses a `300 pt` logical width
- Pixels and density: source `384 × 1298 px`; implementation full capture `1226 × 768 px`; both inspector regions normalized to `216 × 745 px` before comparison
- State: light appearance, SRT imported, first subtitle selected, playback paused, inspector visible

## Findings

- Latest playback-caret screenshot: `/var/folders/0h/k8nffn9j7j334rfbhy768c80000gn/T/com.openai.sky.CUAService/SubForge Screenshot 2026-09-01 at 10.47.03 PM.jpeg`; the active subtitle row shows the blue caret at the current text position while playback is running.
- Playback follow: during SRT playback, the selected subtitle advanced with the current time, the list scrolled to keep it visible, and the playback caret moved continuously across the active subtitle text. In edit mode, the native text editor retains its blinking insertion caret.
- Pause-to-edit: the pause transition captures the current subtitle and UTF-16 caret offset before stopping playback, then restores that offset after the native text editor becomes first responder; the text entry remains settable and accepts navigation keys instead of falling back to the end of the text.

- No actionable P0, P1, or P2 differences remain after applying the user's final typography, spacing, color, and toolbar adjustments.
- Fonts and typography: the three section headings use one shared `16 pt` semibold token. Field labels, action names, project metadata, and the footer use one shared `12 pt` secondary token. Time values and shortcut symbols were also reduced by `2 pt` in the earlier pass. The final typography is intentionally smaller than the original reference because the user explicitly requested that adjustment.
- Spacing and layout rhythm: section order, full-width separators, stacked time fields, compact text editor, five action rows, project metadata, and fixed bottom shortcut entry match the selected hierarchy. Internal section padding, field gaps, action-row gaps, and project-row gaps were reduced in the final pass.
- Colors and visual tokens: system-adaptive semantic colors preserve the reference's neutral hierarchy. Split and delete now use the same black-and-white treatment as the other editor actions.
- Image quality and assets: the target contains no raster assets. All icons use matching macOS SF Symbols and remain sharp at native density.
- Copy and content: all labels and action names match the requested Chinese UI. Shortcut symbols are separated for readability.
- Interaction and accessibility: the inspector text area is exposed as a settable text entry area; time fields are settable; action rows and the bottom shortcut guide remain native buttons with help labels.
- Shortcut guide: the redundant “字幕编辑工作台” subtitle is removed. Each command now occupies a distinct row with `16 pt` vertical padding and a full-width divider; `14 pt` bold, primary-color keycaps make the shortcut column visibly stronger than the explanation. The “完成” action reuses the workbench's secondary header-button style.
- Focus behavior: the shortcut guide's “完成” button keeps the default-action keyboard shortcut but disables the automatic focus-effect ring, so opening the page no longer adds a blue outline. Return was verified to close the sheet successfully.

## Comparison History

1. Initial implementation used larger `20 pt / 14 pt` heading and secondary typography. The hierarchy and section proportions passed structural comparison, but the user requested a uniform reduction.
2. Final implementation reduced inspector heading, secondary text, time values, text editor content, shortcut labels, and action icons by `2 pt`. The post-fix normalized comparison is `/tmp/SubForge-design-comparison.png`.
3. The inspector was compacted, the inactive preview pill was removed, and editor actions were normalized to black and white. The toolbar export and inspector buttons now share one exact `34 pt` height, `7 pt` radius, regular-weight typography, and matching horizontal padding; only their primary and secondary colors differ.
4. The inspector's first section received an additional `8 pt` top inset, aligning the “当前字幕” baseline with the “隐藏右栏” button. All three inspector section headings were reduced from `18 pt` to `16 pt` while secondary text stayed unchanged.
5. Editor shortcut badges were increased from `9 pt` to `11 pt`, and the inspector text editor content was increased from `11 pt` to `13 pt`. The final screenshot confirms the shortcut labels remain single-line and fit their rows without compression.
6. The export and inspector-toggle button typography was reduced from `14 pt` to `12 pt`; both buttons retain the same fixed height and geometry.
7. The complete shortcut guide was widened to `700 pt`, row spacing and column separation were increased, row dividers were added, and shortcut keycaps were enlarged and darkened. The final screenshot confirms `Tab / Shift + Tab` and the multi-modifier insert shortcuts remain legible and grouped correctly.
8. The playback-to-edit transition was hardened so the initial caret captured at pause cannot be overwritten by the text view's default first-focus selection; the post-focus restoration was verified with a local playback smoke test.

## Focused Region Evidence

- The normalized side-by-side inspector comparison was used for the right inspector. The final full app screenshot was used for the toolbar focused region, confirming equal button heights, regular font weight, and removal of the preview pill.

## Follow-up Polish

- P3: the source mock uses a slightly cooler fixed background. The implementation keeps semantic macOS colors so dark mode and system appearance continue to work.

final result: passed
