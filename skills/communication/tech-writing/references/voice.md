# The user's voice

Distilled from the user's own reports and guides. Match it unless a document's audience needs something else.

## Keep

- **Vietnamese prose, English engineering terms as spoken**: pipeline, config, benchmark, frame, latency, build, deploy, engine, flat region, texture. Don't translate them, don't italicise them, and put identifiers in backticks (`site_stride`, `detector_int8.json`).
- **Header block**: bold `**Ngày**:` and `**Dữ liệu**:` lines under the title, listing exactly what the numbers rest on.
- **Answer in a blockquote** right after the header: `> **Dùng X cho cả 2 camera** (…)`, then a short "Lý do ngắn gọn" paragraph.
- **Numbered sections** (`## 1. Kết quả`, `## 2. Phương pháp` — results before method), subsections `### 2.1`.
- **Tables carry the comparison**, values as `% so với baseline` where a baseline exists, the best value in bold, then a 1–3 sentence "đọc số liệu" paragraph that explains what the table means — including when a raw number is misleading.
- **"Vì sao không phải X"** as a short numbered list when a plausible alternative was rejected.
- **"Giới hạn cần biết"** and **"Việc cần làm tiếp"** close every report, as short bullet lists.
- **Guides**: a version table for the environment, numbered steps, `bash` blocks with short `#` comments, a **Lưu ý** list for gotchas, links to the source doc for detail.
- **Document map**: a final table `| Tài liệu | Nội dung |` when a report is one of several.
- Links to scripts and raw data by relative path; external data by a named link ("tải về tại đây").
- Citations as author, venue, year, plus arXiv/DOI link.

## Drop (these slipped into past documents and the user doesn't want them)

- Session narrative: "lỗi đã phát hiện và sửa hôm nay", "lịch sử tune lộn xộn hôm nay", "phải thử … rồi bỏ".
- CAPS for emphasis (KHÔNG, THẤP NHẤT, TỆ hơn) and "!" after numbers.
- Long parenthetical asides and stacked em dashes inside a sentence.
- An intro paragraph that lists what each section will cover.
- Multi-paragraph debugging stories in guides — replace with a troubleshooting row.
- Defensive lines ("không nên hiểu đơn giản là…", "đây không phải điểm yếu").

## Before → after

**Before** (report, results paragraph):
> Đọc số liệu: X có `texture_std` tuyệt đối THẤP NHẤT trong 3 — nhưng đây không phải điểm yếu. `selectivity` (tỷ lệ tăng cường texture thật so với vùng phẳng) của X lại CAO NHẤT — nghĩa là X tăng cường ĐÚNG chỗ có chi tiết thật, ít lan sang vùng nhiễu hơn A/B.

**After**:
> X có `texture_std` thấp nhất nhưng `selectivity` cao nhất (8.95): chi tiết được tăng ở vùng có texture thật, vùng phẳng ít bị khuếch đại nhiễu hơn A và B.

**Before** (guide, a 10-line paragraph about why the jitter buffer must be 200 ms, how it was measured, what the screen looked like).

**After** (one row in "Sự cố thường gặp"):
> | Luồng SR hiện khối xanh lá, luồng gốc vẫn chạy | Frame SR lớn hơn, `rtpjitterbuffer latency=30` loại gói trước khi ráp đủ frame | Dùng `latency=200` |
