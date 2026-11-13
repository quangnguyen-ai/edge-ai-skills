# Prompt templates

Short on purpose: fill the brackets, delete lines that don't apply. Vietnamese prose, English technical terms. `@path` points Claude at a file.

## Sửa bug

```
<Triệu chứng cụ thể> khi <điều kiện>, trên <board/config>. Log: <dán log hoặc @logs/run-xxx.log>.
Nghi ở <@file hoặc module> (nếu biết).
Viết check tái hiện lỗi trước, rồi sửa nguyên nhân gốc — không che triệu chứng.
Xong khi: <check> pass trên board, output khác không đổi.
```

## Thêm tính năng

```
Thêm <tính năng> vào <@module>, để <lý do / ai dùng>.
Làm theo cách <@file mẫu có sẵn> đang làm.
Không đổi: <public API / config đã ship / …>.
Lên plan trước, chờ t duyệt rồi mới code.
Xong khi: <test / lệnh / số đo>.
```

## Tối ưu hiệu năng

```
<Stage/kernel> đang <số đo hiện tại, p50/p99> trên <board, power mode>, budget là <số>.
Đo trước để tìm bottleneck, đề xuất 2–3 hướng có ước lượng lợi/rủi ro, chờ t chọn.
Ràng buộc: output bit-exact (hoặc trong noise band), không đổi config.
Xong khi: A/B xen kẽ trên board cho thấy <mục tiêu>.
```

## Thí nghiệm / so sánh

```
Giả thuyết: <…>. So sánh <A> và <B> trên <dữ liệu, N frame đầu>.
Metric: <…>. Lưu vào experiments/<tên>/, có ảnh full-res.
Kết luận theo cơ chế, không chỉ theo số.
```

## Report / docs

```
Viết <loại: report / guide / overview / MR description> về <chủ đề> cho <người đọc>.
Nguồn: <@files, @logs, kết quả trong experiments/…>.
Họ cần <quyết định / làm được gì> sau khi đọc.
Lưu ở <docs/...>. Tiếng Việt.
```

## Diagram

```
Vẽ <luồng / kiến trúc / thread / state> của <hệ thống> cho <người đọc>.
Phong cách như <@file mẫu> (nếu khác mặc định).
Lưu ở <docs/diagrams/>, mở ảnh cho t xem.
```

## Review code

```
Review <diff từ <commit/branch> / @file> theo <checklist / spec @…>.
Chỉ báo lỗi ảnh hưởng tới đúng đắn hoặc yêu cầu, không báo style.
```

## Hỏi để hiểu

```
<Câu hỏi cụ thể>, trong <@repo/@file>. Trả lời ngắn, chỉ ra file:dòng.
```

## Làm quen repo mới

```
Onboard repo <đường dẫn>, tập trung vào <phần t sẽ làm>.
Board: <host>. Kết quả: CLAUDE.md, overview + sơ đồ, glossary, câu hỏi cho team.
```

## Phrases that change behaviour

| Muốn | Nói |
|---|---|
| Chỉ phân tích, chưa sửa | "chỉ đề xuất, chưa code" |
| Code luôn | "code luôn" / "sửa đi" |
| Chờ duyệt plan | "lên plan, chờ t duyệt" |
| Không commit | (mặc định) — "commit đi" khi muốn |
| Ngắn | "trả lời ngắn" / "chỉ kết luận" |
| Tự kiểm chứng | "chạy <lệnh> để xác nhận" |
| Bỏ qua cái đang dở | "bỏ cái đó, làm <…>" |
