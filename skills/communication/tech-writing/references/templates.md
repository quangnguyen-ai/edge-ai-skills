# Templates

Section names are in Vietnamese because that is the default output language; use the reader's language. Drop any section that would be empty — never write "N/A" sections.

## Report (evaluation / experiment / benchmark)

```markdown
# <Kết quả chính, viết như một câu khẳng định — không phải tên đề tài>

**Ngày**: YYYY-MM-DD · **Dữ liệu**: <tập dữ liệu, số mẫu, điều kiện> · **Thiết bị**: <board, SDK, power mode> · **Commit**: <hash>

> **Kết luận**: <1–3 câu: kết quả + hành động đề xuất>

## 1. Kết quả

| <cấu hình> | <metric 1> | <metric 2> | <metric 3> |
|---|---|---|---|
| A | … | **best** | … |
| B | … | … | … |

<1–2 câu: bảng cho thấy điều gì, và vì sao nó dẫn tới kết luận.>

<Ảnh minh hoạ nếu cần — full-res, có chú thích một dòng.>

## 2. Phương pháp

- Metric: <định nghĩa ngắn từng metric, đơn vị>
- Cách đo: <warm-up, số lần lặp, p50/p99, cố định clock…>
- Script: `<path>` · Dữ liệu thô: `<path>`

## 3. Giới hạn

- <điều chưa được kiểm chứng và vì sao nó có thể đổi kết luận>

## 4. Bước tiếp theo

- <việc cụ thể, sẽ trả lời câu hỏi gì>
```

Rules: the title states the finding ("INT8 giữ mAP trong 0.5 điểm, giảm latency 40%"), not the topic ("Đánh giá quantization"). Methods come *after* results — the reader reaches the answer before the procedure.

## Recommendation / decision

```markdown
# Khuyến nghị: <lựa chọn>

**Ngày**: … · **Người quyết định**: … · **Cần quyết trước**: …

> **Dùng <X>** cho <phạm vi>. <Một câu lý do chính.>

## So sánh

| Tiêu chí | X | Y | Z |
|---|---|---|---|

## Vì sao không chọn Y, Z

- **Y**: <một dòng lý do>
- **Z**: <một dòng lý do>

## Rủi ro và cách giảm

- <rủi ro> → <biện pháp>
```

## Status update (weekly / sprint)

```markdown
# <Dự án> — tuần <N> (<từ ngày> → <đến ngày>)

**Kết quả**
- <việc đã xong — kết quả đo được, link>

**Đang làm**
- <việc> — dự kiến xong <ngày>

**Cần hỗ trợ / vướng**
- <vướng gì, cần ai, trước khi nào>
```

5–12 lines. Results, not activities ("latency p99 32 → 21 ms", not "đã tối ưu preprocess").

## Guide (how-to: build, run, deploy, train)

```markdown
# <Làm X> — <trên Y>

<1–2 câu: dùng khi nào, kết quả cuối cùng là gì.>

## Yêu cầu

| Thành phần | Phiên bản |
|---|---|

## 1. <Bước>

```bash
<lệnh copy-paste được, có comment ngắn khi lệnh không tự giải thích>
```

<Kết quả mong đợi: dòng log / file sinh ra / cách kiểm tra.>

## 2. <Bước> …

## Tuỳ chọn chính

| Option | Mặc định | Ý nghĩa |
|---|---|---|

## Sự cố thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
```

Each step ends with how to verify it worked. History of how a problem was discovered goes nowhere; its fix goes in the troubleshooting table.

## Reference (config keys, API, CLI)

```markdown
# <Thành phần> — tham chiếu

| Key | Kiểu | Mặc định | Ý nghĩa | Ghi chú |
|---|---|---|---|---|
```

Alphabetical or grouped by stage; one row per item; no prose between rows. Defaults copied from code, with the file they live in.

## Overview (architecture / explanation)

```markdown
# <Hệ thống> — tổng quan

<2–3 câu: hệ thống làm gì, cho ai, giới hạn phạm vi.>

![<sơ đồ>](diagrams/<file>.png)

## Thành phần

| Thành phần | Vai trò | Code |
|---|---|---|

## Luồng xử lý

<đoạn ngắn theo thứ tự luồng, khớp với sơ đồ>

## Tài liệu liên quan

| Tài liệu | Nội dung |
|---|---|
```

## Commit message

English unless the repo's history is in another language. Match the repo's existing prefixes.

```
<area>: <imperative summary, ≤ 72 chars, no trailing period>

<What changed and why, in 1–3 short paragraphs or bullets — one bullet per
logical change when there are several. Name the kernels, functions, config
keys involved.>

New keys: <key_a>, <key_b> (defaults keep the old behaviour).
Verified: <how — bit-exact md5 over N frames / test X / board Y>.
Cost: <measured delta, e.g. +0.1 ms/frame on the stage bench> — or say the
change is structural and was not measured.
```

- Subject says what the commit does ("Cut host round-trips out of OpenCL registration"), not what was worked on ("registration optimisation").
- Body: final state and reason. No development story ("first tried…", "used during debugging to isolate…").
- Pure tuning commits say so: "Display tuning only; no code path changes."
- No `Co-Authored-By` or any assistant attribution line.

## MR / PR description

```markdown
## Tóm tắt
<2–3 câu: thay đổi gì, vì sao, ảnh hưởng tới ai/cái gì.>

## Thay đổi
- <thay đổi 1 — file/module chính>
- <thay đổi 2>

## Kiểm chứng
| Kiểm tra | Môi trường | Kết quả |
|---|---|---|
| <test / bench / so sánh bit-exact> | <board, config, dữ liệu> | <pass, số đo> |

## Ảnh hưởng tới config / API
- <key mới + mặc định, key đổi tên, migration> — hoặc "Không có".

## Chưa kiểm chứng / rủi ro
- <board, mode, kịch bản chưa chạy>
```

Reviewers read the summary and the verification table first: make both answerable without opening the diff. Screenshots or before/after images for any visual change (full resolution, labelled).
