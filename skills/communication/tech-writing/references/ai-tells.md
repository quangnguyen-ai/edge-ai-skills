# Patterns that make text read machine-written

Check every draft against this list and rewrite each hit. Adapted from the Wikipedia "Signs of AI writing" catalogue (via the open-source *humanizer* skill), extended with Vietnamese patterns and report-specific ones. A pattern seen once in a long document is fine; a pattern that repeats is the tell.

## Structure

| Pattern | Example | Fix |
|---|---|---|
| Intro that announces the sections | "Tài liệu này giới thiệu… (mục 1-2), làm rõ… (mục 3), so sánh… (mục 4)…" | Start with the content. A table of contents is the reader's job. |
| Heading restated in the first sentence | "## Kết quả — Phần này trình bày kết quả…" | Delete the sentence. |
| Summary/closing that repeats the body | "Tóm lại, …", "Nhìn chung, …", a final paragraph re-listing findings | Delete it; the conclusion is already at the top. |
| Writing about the document | "Tài liệu này được viết để…", "như đã đề cập ở trên" | Describe the subject, not the text. |
| Session history | "lỗi đã phát hiện và sửa hôm nay", "trong session này", "sau nhiều lần thử" | Report the current state only. |
| Failed-attempt narrative | "ban đầu thử A, không được, chuyển sang B…" | Final result; at most one "why not A" line. |
| Debug story in a guide | a 10-line paragraph explaining how a bug was found | One row in a symptom → cause → fix table. |

## Sentences

| Pattern | Example | Fix |
|---|---|---|
| Not X but Y / "không chỉ… mà còn" | "Đây không chỉ là bước tiền xử lý mà còn là…" | State the claim directly. |
| Arguing with nobody | "không nên hiểu đơn giản là…", "đây không phải điểm yếu" (nobody said it was) | Delete the defence; keep the fact. |
| Inflated significance | "đóng vai trò then chốt", "bước quan trọng nhất", "mở ra hướng đi mới" | Say what it does, with a number if there is one. |
| Empty -ing / riders | "…, cho thấy hiệu quả vượt trội", "…, góp phần nâng cao chất lượng" | Cut, or replace with the measured effect. |
| Vague link | "liên quan tới", "gắn liền với", "có ảnh hưởng đến" with no mechanism | Name the relationship, or cut. |
| Stacked hedges | "có thể phần nào giúp cải thiện đáng kể" | One qualifier the data supports. |
| Forced triads | "nhanh, gọn, hiệu quả" when only one is shown | Keep the items with evidence. |
| Repeated openings | three sentences starting with the same subject / "Điều này…" | Merge or start with the action. |
| Avoiding plain verbs | "đóng vai trò là", "sở hữu", "mang đến" | "là", "có". |
| Buzzwords (EN) | delve, crucial, robust, seamless, leverage, comprehensive, showcase, landscape | Plain words. |
| Buzzwords (VI) | "toàn diện", "vượt trội", "tối ưu" (unmeasured), "một cách hiệu quả", "đáng chú ý là", "không thể phủ nhận", "hãy cùng tìm hiểu" | Plain words or a number. |
| Borrowed authority | "nhiều nghiên cứu cho thấy" with no citation | Cite the paper, or cut. |

## Formatting

| Pattern | Example | Fix |
|---|---|---|
| ALL CAPS emphasis | "KHÔNG dùng dữ liệu cũ", "THẤP NHẤT" | Normal case; bold at most one key value. |
| Bold everywhere | bold label on every bullet, bold mid-sentence phrases | Bold only the answer and table winners. |
| Dash as universal connector | "—" in every second sentence | Commas, colons, full stops. At most one dash per paragraph. |
| Parenthetical asides inside asides | "(0.40×–0.89× nếu tính theo chiều …)" mid-sentence | Move to a table or a footnote line, or cut. |
| Exclamation and hype in numbers | "191%!", "thắng rõ ràng ở mọi thước đo" | The number, plainly. |
| Decorative headings | emojis, arrows, "🚀 Kết quả", title-case English headings | Plain headings that name the content. |
| Horizontal rules between every section | `---` after each `##` | Headings already separate sections. |
| Chat residue | "Dưới đây là…", "Hy vọng tài liệu hữu ích", "Bạn có thể…" | Delete. |

## Final check

Read the first 5 lines: do they give the answer? Read only the headings: do they tell the story? Search the draft for "hôm nay", "session", "đã thử", "tóm lại", "nhìn chung", "không chỉ", "—", and words in CAPS — each hit needs a reason to stay.
