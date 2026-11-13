# Failure patterns

Each pattern: what it looks like, what goes wrong, the fix. Examples are real request shapes (project names removed).

| Pattern | Looks like | What goes wrong | Fix |
|---|---|---|---|
| **Ambiguous pointer** | "chuyển vào phần đó", "sửa cái kia luôn", "để nó vào đó" | Claude guesses which "đó"; a wrong guess costs a round-trip | Name it: skill, file, section. "chuyển phần CUDA trong `cpp-engineering` sang `gpu-kernel-engineering`" |
| **Style in adjectives** | "màu trung tính", "đẹp hơn", "chuyên nghiệp" | Each adjective has many readings; the first result misses, then "đơn điệu quá" | Point at a sample: "giống `@docs/…/stage.svg`". One example beats three rounds of adjectives |
| **No done-check** | "tối ưu cái này", "fix build" | Claude stops when it *looks* done | Add the check: "xong khi `make` pass trên board và p99 < 20 ms" |
| **Missing where** | "build thử đi" (which board?), "lưu lại" (where?) | Wrong target, wrong place | Board, path, repo in the prompt — or in CLAUDE.md so it's never needed again |
| **Several tasks in one line** | "vẽ kiến trúc, viết report, rồi tối ưu luôn" | One gets done well, the others thinly | One prompt per task, or list them numbered and say the order |
| **Question that is really an instruction** (or the reverse) | "có thêm được không?" meaning "thêm đi" | Claude answers instead of acting — or acts when only an answer was wanted | Say which: "thêm đi" vs "chỉ trả lời, chưa làm" |
| **Assuming Claude can see it** | "hình output đâu" (window on the desktop), a chat link, "cái lúc nãy t nói" in a new session | Claude can't see desktop windows, private chat links, or other sessions | Paste the content, give the file path, or say where the output should appear |
| **Preference revealed only after the result** | first ask "nền trắng", then reject the result | Rework | State taste up front with a sample; durable tastes go into CLAUDE.md once |
| **Unscoped investigation** | "tìm hiểu cái repo này" | Reads hundreds of files, fills context | Scope: which part, which question, how deep — or "dùng subagent tìm hiểu …" |
| **Correcting in circles** | third "không phải vậy" on the same thing | Context fills with failed attempts | `/clear`, then one prompt that includes what was learned |
| **Hidden constraint** | after the fix: "không được đổi config" | Valid work thrown away | Constraints in the first prompt, or in CLAUDE.md if they always hold |

## Rewrite examples

**Before**: `Đơn điệu quá, nền trắng thôi`
**After**: `Vẽ lại diagram vòng đời: nền trắng, box giống @docs/pipeline/stage.svg (màu nhạt theo nhóm, khung nét đứt, badge số). Mở ảnh cho t xem.`
*Added — Example: the reference file; Output: open the image.*

**Before**: `tối ưu preprocess đi`
**After**: `Preprocess đang 6 ms/frame (p50) trên board Orin, budget 3 ms. Đo trước tìm bottleneck, đề xuất 2–3 hướng, chờ t chọn. Output phải bit-exact. Xong khi A/B xen kẽ trên board < 3 ms.`
*Added — Context: current number and board; Constraints: bit-exact; Done-check: paired A/B.*

**Before**: `viết report kết quả AGC`
**After**: `Viết report so sánh 3 cấu hình AGC từ experiments/2026-10-agc/ cho trưởng nhóm, để chọn cấu hình ship. Kết luận đầu tiên, có bảng + ảnh full-res, lưu docs/reports/2026-10-agc.md.`
*Added — Goal: the decision; Context: data source; Output: reader, location.*
