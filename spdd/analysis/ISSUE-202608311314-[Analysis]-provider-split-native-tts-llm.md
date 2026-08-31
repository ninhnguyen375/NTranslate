# SPDD Analysis: Tách provider LLM/TTS, TTS native macOS, và đánh giá Apple Intelligence

## Original Business Requirement

vậy chốt lại:
- tách riêng apikey + url cho phần LLM và TTS
- phần setting TTS sẽ cho phép chọn native macos hoặc api, nếu là api thì cung cấp thêm api-key và url
- nút retryButton khi bấm sẽ clear luôn phần cache audio (để giúp user call lại TTS theo setting mới)
- phân tích và test thử model local của apple intelligence xài được không, nếu xài được thì phần setting api LLM cũng cho phép chọn native apple intelligence (test thử và so sánh kết quả khi dùng các prompt cho từng tính huống translate/learn/proofread/Q&A hỗ trợ đa ngôn ngữ, nhất là tiếng Việt)

Bối cảnh dẫn tới yêu cầu (từ hai lượt phân tích trước trong cùng phiên):

- App hiện gọi TTS qua 9router bằng model prefix `edge-tts/`, tức đã dùng Edge TTS miễn phí, không phải OpenAI TTS.
- Benchmark thực đo trên máy dev: Edge warm 0.35-0.79 s, cold 2.0-8.4 s; native macOS 17-720 ms. Native nhanh hơn 5-15x warm, 50-100x cold.
- Native xuất PCM thô: bản dài 3.261 KB so với 85 KB MP3 của Edge, gấp ~38 lần.
- Rủi ro chính không phải tốc độ mà là độ sẵn sàng: 9router chạy trên `ninh-pc` qua Tailscale, máy tắt là mất TTS hoàn toàn.

## Locked Decisions

Chốt bởi user sau khi đọc kết quả test, trước khi viết code. Các mục dưới đây **không còn mở**; phần Strategic Approach và Risk & Gap bên dưới đã được viết lại theo chúng.

| # | Quyết định | Hệ quả |
|---|---|---|
| D1 | **Bỏ hẳn Apple Intelligence.** Không đưa vào làm LLM provider, kể cả phương án proofread-only. | AC4 đóng lại với kết luận "không triển khai". `LLMProvider` không còn là khái niệm cần thiết. Kết quả test giữ lại làm căn cứ, không làm đầu vào thiết kế. |
| D2 | **Key TTS để trống thì kế thừa key LLM.** Hai key vẫn tách được, nhưng TTS chỉ dùng key riêng khi user nhập tường minh. | Di trú Keychain trở nên tầm thường: không cần sao chép key cũ sang scope mới. Bản cài hiện có chạy tiếp không cần thao tác gì. |
| D3 | **Vô hiệu hóa audio cache chỉ trong phạm vi bản ghi đang xem.** Không đụng audio của các bản ghi history khác. | Xóa `speechCache`/`speechTrim` theo `recordID` hiện tại, cộng audio đã lưu trong history của riêng bản ghi đó. |

## Domain Concept Identification

### Existing Concepts (from codebase)

- **Credential (API key)**: một chuỗi bí mật duy nhất trong Keychain, service `local.ninh.ntranslate`, account `apiKey` (`APIKeyStore.swift:5`). Hiện là **singleton toàn app** — không có khái niệm "key thuộc về provider nào".
- **Endpoint**: `AppConfig.apiBaseURL` và `AppConfig.apiSpeechURL`. Đã là hai field riêng, nhưng ghép cứng: khi config thiếu `apiSpeechURL`, giá trị được **suy ra** từ `apiBaseURL` bằng phép thay chuỗi `/chat/completions` → `/audio/speech` (`AppConfig.swift:308`). Đây là giả định "hai dịch vụ cùng một host".
- **Translator**: một struct duy nhất giữ `config` + `apiKey`, phục vụ **cả** LLM (`translate`, `learn`, `proofread`, Q&A) lẫn TTS (`speak`). Được khởi tạo tại đúng hai chỗ (`PopoverController+Menu.swift:411`, `SettingsWindowController.swift:668`). Một credential, một đối tượng, hai trách nhiệm.
- **SpeechIdentity**: khóa định danh một clip audio, gồm `kind` (source/result), `text`, `model`, `recordID`. Là khóa của toàn bộ tầng cache.
- **Speech cache (in-memory)**: `speechCache: [SpeechIdentity: Data]` và `speechTrim: [SpeechIdentity: Bounds]` (`PopoverController.swift:165-166`).
- **Speech cache (persistent)**: audio được ghi vào history store qua `attachAudio` (`PopoverController+Speech.swift:333`) và nạp lại bằng `hydrateStoredAudio` (`:106`). Đây là tầng cache **thứ hai**, sống lâu hơn phiên chạy.
- **SpeechModelResolver**: map tên ngôn ngữ → model string (`speechModels[language] ?? speechFallbackModel`). Model string hiện mang cả ý nghĩa provider (`edge-tts/...`) lẫn voice.
- **Prefetch pipeline**: `autoPrefetchSpeech` + `speechPrefetchMaxLength` (300) tự tải audio ngay sau khi dịch xong, che gần hết độ trễ mạng.
- **Retry action**: `retryRequest` (`PopoverController+Actions.swift:163`) và `retrySubRequest` (`PopoverController+Subtranslate.swift:382`). Ý nghĩa hiện tại là "gọi lại LLM, bỏ qua cache history" (`bypassCache: true`).
- **Execution mode**: `lastExecutionMode` phân nhánh translate/learn/proofread — mỗi nhánh có prompt riêng trong config.

### New Concepts Required

- **SpeechProvider**: nguồn sinh audio, hai giá trị `native` và `api`. Khái niệm mới vì hiện tại chỉ tồn tại ngầm định một nguồn duy nhất.
- ~~**LLMProvider**~~: **loại bỏ theo D1.** Chỉ còn một nguồn sinh văn bản là API, đúng như hiện tại. Không có khái niệm mới nào phát sinh ở phía LLM.
- **Credential scope**: khái niệm "key này thuộc dịch vụ nào". Theo D2, Keychain có thêm **một** entry tùy chọn cho TTS; khi entry đó vắng mặt thì key LLM được dùng. Không cần di trú key cũ.
- **Voice identity (native)**: với provider native, thứ thay thế `model` không phải model string mà là `AVSpeechSynthesisVoice.identifier`. Cùng vị trí trong `SpeechIdentity` nhưng khác không gian giá trị.
- **Audio cache invalidation**: hành vi chủ động xóa cả cache RAM lẫn audio đã lưu trong history cho bản ghi đang xem. Hiện chưa tồn tại dưới bất kỳ hình thức nào.

### Key Business Rules

- **Một danh tính audio phải khóa được provider**: hai clip cùng text, cùng ngôn ngữ nhưng khác provider là hai clip khác nhau. Nếu `SpeechIdentity` không phân biệt được, đổi setting sẽ trả về audio cũ của provider cũ.
- **Đổi setting TTS phải làm audio cũ vô hiệu**: đây chính là lý do nghiệp vụ đằng sau yêu cầu retryButton. Retry là *một* đường kích hoạt, không phải đường duy nhất.
- **Key TTS vắng mặt nghĩa là dùng chung key LLM** (D2). Đây vừa là quy tắc nghiệp vụ vừa là cơ chế tương thích ngược: user đang chạy một key duy nhất sẽ không phải nhập lại gì.
- **TTS hỏng không được làm hỏng dịch**: hai dịch vụ độc lập thì lỗi cũng phải độc lập. Hiện `Translator` gộp chung nên ranh giới này chưa rõ.
- **Provider native phải hoạt động không cần mạng**: đây là toàn bộ giá trị của nó. Nếu vẫn phụ thuộc bất kỳ thứ gì online thì không đạt mục tiêu.
- **Dung lượng history phải giữ ở mức cũ**: audio native thô lớn gấp ~38 lần. Ghi thẳng vào history vi phạm ràng buộc này.
- **Ngôn ngữ nào không có voice native thì phải nói rõ**, không im lặng phát sai giọng. Máy dev chỉ có `vi-VN.Linh` bản compact và `zh-CN.Tingting` super-compact; enhanced/premium không cài sẵn và app không tự tải được.

## Strategic Approach

### Solution Direction

Yêu cầu gồm bốn điểm nhưng chỉ có **ba** mức độ chín khác nhau, nên hướng giải quyết là tách chúng ra thay vì gộp thành một thay đổi.

**Nhóm A - Tách trách nhiệm credential và endpoint (nền tảng).** Chuyển `Translator` từ "một đối tượng hai trách nhiệm" sang hai đường cấu hình độc lập: một cho LLM, một cho speech, mỗi bên có URL và key riêng. Keychain chuyển từ một entry sang nhiều entry theo scope. Đây là điều kiện tiên quyết cho nhóm B, và tự nó đã có giá trị: user có thể trỏ TTS sang một 9router khác hoặc một nhà cung cấp khác mà không đụng LLM.

**Nhóm B - SpeechProvider hai nhánh.** Thêm nhánh `native` bên cạnh `api`, cùng trả về `Data` để toàn bộ tầng dưới (cache, trim, `AVAudioPlayer`, history) không đổi. Đây là điểm mấu chốt về kiến trúc: hợp đồng `speak(text, model, speed) -> Data` đã đúng sẵn, nhánh mới chỉ cần tôn trọng nó. Kèm theo là bước encode nén trước khi lưu history, và mở rộng `SpeechIdentity` để phân biệt provider.

**Nhóm C - Vô hiệu hóa audio cache.** Yêu cầu nêu retryButton, nhưng phân tích cho thấy đây là triệu chứng của một lỗ hổng rộng hơn (xem Risk & Gap). Hướng đúng là một điểm vô hiệu hóa dùng chung, được gọi từ cả retry lẫn nơi lưu setting TTS.

**Nhóm D - Apple Intelligence: loại khỏi phạm vi (D1).** Đã test thực tế, không đạt điều kiện "nếu xài được" của yêu cầu. Kết quả giữ lại bên dưới làm căn cứ cho quyết định, không phải đầu vào thiết kế.

Sau khi chốt D1, phạm vi công việc còn lại **hoàn toàn nằm ở phía TTS và credential**. Tầng LLM không đổi ngoài việc `Translator` thôi kiêm nhiệm TTS.

### Kết quả test Apple Intelligence Foundation Models

Môi trường: macOS 26.6.2 (build 25G83), `FoundationModels.framework` có trong SDK, Apple Intelligence đã bật, `SystemLanguageModel.default.availability` trả về **`.available`**. Tiếng Việt **có** trong `supportedLanguages` (`vi-Latn-VN`), cùng 22 locale khác.

Test dùng đúng bốn prompt trong `config.json` hiện tại của user.

| Tình huống | Kết quả | Thời gian |
|---|---|---|
| translate en→vi (thành ngữ) | **Fail** - trả nguyên văn tiếng Anh, không dịch | 3.11 s |
| translate en→vi (kỹ thuật) | **Fail** - không dịch; bịa thêm mục "phát âm Trung Quốc: 漏出连接池" | 3.16 s |
| translate zh→vi | **Fail** - không dịch; rò placeholder `<cụm gốc>`, `<từ/cụm gốc>` ra output trong code fence | 1.52 s |
| learn (phrasal verb) | **Fail cứng** - `exceededContextWindowSize`: "Content contains 4091 tokens, which exceeds the maximum allowed context size of 4096" | - |
| learn (từ đơn) | **Fail** - rò **toàn bộ** khối "Hard rules" của system prompt ra output; để nguyên placeholder; ghi "Phiên âm: (không có)" cho một từ tiếng Anh | 11.86 s |
| proofread | **Pass** - sửa đúng, đúng định dạng, giải thích tiếng Việt chuẩn | 0.77 s |
| Q&A tiếng Việt | **Pass một phần** - nội dung đúng, tiếng Việt trôi chảy, nhưng dùng markdown `**` mà prompt cấm | 2.33 s |

Test đối chứng với prompt tối giản ("Translate from English to Vietnamese. Output only the translation.") để tách bạch "FM không dịch được" khỏi "prompt của app quá phức tạp":

- "It's raining cats and dogs." → **"Đông máu."** Sai hoàn toàn, không liên quan nghĩa gốc.
- "The connection pool leaked because the transaction was never committed." → "Vị trí lưu trữ kết nối bị rò rỉ vì giao dịch chưa được thực hiện." Chấp nhận được về ngữ pháp nhưng sai thuật ngữ ("connection pool" thành "vị trí lưu trữ kết nối") và mất khái niệm commit.

Test sinh tiếng Việt thuần (không dịch): trôi chảy, đúng ngữ pháp, tự nhiên.

**Kết luận**: FM viết tiếng Việt tốt nhưng **dịch không đáng tin** và **tuân thủ chỉ dẫn yếu**. Hai rào cản cứng:

1. **Context window 4096 token cho cả input lẫn output.** `learnPrompt` một mình đã chiếm 4091 token. Không có cách nào lách ngoài việc viết lại prompt ngắn hơn nhiều, mà làm vậy thì mất chính những ràng buộc định dạng tạo nên giá trị của tính năng. Đồng thời `maxTranslateLength` hiện là 5000 ký tự, vượt xa cửa sổ này.
2. **Rò system prompt ra output.** Với một app dịch thuật, người dùng nhận về nguyên khối "Hard rules" thay vì bản dịch là lỗi không thể chấp nhận.

### Key Design Decisions

- **Phạm vi Apple Intelligence**: **đã chốt D1 — loại hoàn toàn.** Không giữ cả phương án proofread-only. Lý do chọn hướng dứt khoát thay vì thu hẹp: một provider chỉ phục vụ một trong bốn tình huống tạo ra một nhánh cấu hình mà user phải hiểu và bảo trì, đổi lại chỉ tiết kiệm được một lệnh gọi mạng 0.77 s cho tính năng ít dùng nhất. Xem xét lại nếu Apple mở rộng context window vượt 4096 token.

- **Vị trí của native trong TTS**: fallback tự động / lựa chọn hiện trong Settings.
  Trade-off: fallback im lặng cho trải nghiệm liền mạch khi 9router chết nhưng user không hiểu vì sao giọng đổi; lựa chọn tường minh thì user kiểm soát được nhưng phải tự xử lý khi API hỏng.
  → **Khuyến nghị làm cả hai**: Settings cho chọn tường minh (đúng yêu cầu), đồng thời native đóng vai trò fallback khi provider `api` lỗi. Chi phí thêm nhỏ vì nhánh native dù sao cũng phải tồn tại.

- **Dung lượng audio native**: lưu PCM thô / encode trước khi lưu.
  Trade-off: PCM thô đơn giản hơn nhưng làm history phình gấp ~38 lần; encode tốn thời gian, ăn lại một phần lợi thế tốc độ của native.
  → **Khuyến nghị encode** (AAC/M4A qua `AVAudioFile` hoặc `AVAssetExportSession`). Native đang nhanh hơn 5-15 lần nên còn dư địa; đổi một phần tốc độ lấy dung lượng là đúng hướng.

- **Phạm vi vô hiệu hóa cache khi retry**: **đã chốt D3 — bản ghi đang xem, cả RAM lẫn history của riêng nó.** Chỉ xóa RAM là không đủ vì `hydrateStoredAudio` sẽ nạp lại audio cũ từ history ngay ở lần mở kế tiếp. Không đụng bản ghi khác: audio cũ của chúng vẫn hợp lệ cho tới khi user chủ động retry từng cái. Đánh đổi được chấp nhận: một bản ghi cũ mở lại vẫn phát giọng của provider cũ.

- **Điểm kích hoạt vô hiệu hóa**: chỉ retryButton / retryButton cộng thời điểm lưu setting TTS.
  Trade-off: chỉ retryButton thì đúng chữ của yêu cầu nhưng user phải nhớ bấm retry sau mỗi lần đổi setting, và mọi bản ghi history khác vẫn giữ audio cũ; thêm điểm lưu setting thì hành vi tự nhiên hơn nhưng phạm vi rộng hơn.
  → **Khuyến nghị cả hai**, với cùng một hàm dùng chung. Đây là ứng dụng trực tiếp của quy tắc sửa tại gốc: một guard trong hàm chung nhỏ hơn một guard ở mỗi nơi gọi.

- **Di trú Keychain**: **đã chốt D2 — không cần di trú.** Entry `apiKey` hiện tại giữ nguyên vai trò key LLM. Thêm một entry tùy chọn cho TTS; khi vắng mặt thì đọc key LLM. Bản cài hiện có chạy tiếp nguyên trạng, không có bước di trú nào để hỏng. Đây là lý do chính khiến D2 tốt hơn phương án hai key độc lập.

- **Quan hệ `apiSpeechURL` với `apiBaseURL`**: giữ suy ra tự động / bỏ hẳn.
  Trade-off: giữ thì tương thích ngược với config cũ; bỏ thì mô hình sạch hơn nhưng config hiện có của user sẽ mất `apiSpeechURL` nếu file thiếu field đó.
  → **Khuyến nghị giữ phép suy ra chỉ như đường di trú cho config cũ**, còn với config mới thì hai URL độc lập hoàn toàn. Sau khi đã tách provider, việc suy ra URL speech từ URL chat là giả định sai về mặt khái niệm.

### Alternatives Considered

- **Viết Edge TTS trực tiếp trong Swift (bỏ 9router)**: loại. Cần WebSocket, SSML, và token `Sec-MS-GEC` mà Microsoft đã đổi nhiều lần; mỗi lần đổi là mất TTS cho toàn bộ bản đã phát hành. 9router đã gánh phần này ở phía server và có thể cập nhật độc lập với app.
- **Rút gọn `learnPrompt` để vừa cửa sổ 4096 token của FM**: loại. Chính các ràng buộc định dạng dài là thứ tạo ra giá trị của tính năng learn; cắt đi thì tính năng còn lại rất ít, mà vẫn không giải quyết được vấn đề rò system prompt. Moot sau D1.
- **Hai API key độc lập hoàn toàn cho LLM và TTS**: loại theo D2. Đúng về mặt mô hình nhưng bắt user hiện tại (một 9router phục vụ cả hai) phải nhập cùng một key hai lần, và tạo ra một bước di trú Keychain có thể hỏng. Kế thừa khi bỏ trống cho cùng khả năng tách mà không có chi phí đó.
- **Xóa audio cache toàn cục khi retry**: loại theo D3. Retry là hành động trên một bản ghi; cho nó xóa audio của mọi bản ghi khác là tác dụng phụ user không yêu cầu và không nhìn thấy được.
- **Dùng FM chỉ để phát hiện ngôn ngữ nguồn**: loại khỏi phạm vi lần này. `LanguageDetector` hiện đã chạy và không nằm trong yêu cầu.
- **Bỏ hẳn provider `api` cho TTS, chỉ dùng native**: loại. Giọng `vi-VN.Linh` bản compact kém `vi-VN-HoaiMyNeural` rõ rệt; đây là bước lùi chất lượng cho ngôn ngữ chính của user.

## Risk & Gap Analysis

### Requirement Ambiguities

Ba điểm mơ hồ ban đầu đã được chốt (xem Locked Decisions): phạm vi clear cache, quan hệ giữa hai key, và phạm vi Apple Intelligence. Còn lại hai điểm cần trả lời trong REASONS Canvas:

- **retryButton nào**: `retryRequest` ở khung chính hay cả `retrySubRequest` ở subtranslate section? Yêu cầu chỉ nói "retryButton". `retrySubRequest` hiện **không** gọi `invalidateSpeech` chút nào, tức đang thiếu cả hành vi cơ bản chứ không riêng phần clear cache. Khuyến nghị: xử lý cả hai qua cùng một hàm, vì đây là cùng một lỗ hổng.
- **Native TTS chọn voice thế nào**: user chọn từng voice cho từng ngôn ngữ (song song với `speechModels` hiện tại), hay app tự chọn voice tốt nhất theo ngôn ngữ? Yêu cầu không nói. Khuyến nghị: tự chọn theo ngôn ngữ, ưu tiên quality cao nhất đang cài; cho override sau nếu cần.

### Edge Cases

- **Bản ghi history có audio sinh bởi provider cũ**: theo D3 chỉ bản ghi đang xem được làm sạch, nên tình huống này là **hành vi chấp nhận được**, không phải lỗi: mở lại một bản ghi cũ sẽ phát giọng của provider cũ cho tới khi user retry nó. Vẫn cần `SpeechIdentity` mang provider để audio cũ không bị nhận nhầm là audio của provider mới trong cùng một phiên.
- **Ngôn ngữ không có voice native**: hiện máy chỉ có voice cho vi/en/zh. Nếu user thêm ngôn ngữ vào `targetLanguages` mà macOS không có voice, nhánh native không có gì để phát.
- **Voice native chưa tải về**: voice Enhanced/Premium phải tải thủ công qua System Settings. App không tải hộ được. `AVSpeechSynthesisVoice(identifier:)` trả `nil` cho voice chưa cài.
- **Voice từ chối `write()`**: một số voice (personal voice, một phần voice Siri) không cho phép ghi ra buffer. Đã gặp trong lúc benchmark.
- **Text vượt `speechPrefetchMaxLength` (300)**: không được prefetch, nên độ trễ lộ ra hoàn toàn. Đúng trường hợp Edge cold 8.4 s. Đây là kịch bản native có giá trị nhất.
- **Đổi setting TTS giữa lúc đang phát**: `audioPlayer` đang chạy clip của provider cũ. Cần dừng, không chỉ vô hiệu cache.
- **Đổi setting giữa lúc prefetch đang bay**: `prefetchingSpeech` chứa identity của provider cũ; kết quả về sau khi đã đổi setting sẽ ghi nhầm vào cache. `prefetchGeneration` hiện có xử lý pattern này, cần đảm bảo đường mới cũng đi qua nó.
- **Key TTS rỗng nhưng provider là `api`**: theo D2 đây là đường hợp lệ, phải rơi về key LLM chứ không báo lỗi. Chỉ khi **cả hai** cùng rỗng mới là lỗi cấu hình, và khi đó phải báo rõ thay vì im lặng gửi request thiếu Authorization (server trả 401 như đã quan sát).
- **Key LLM đổi trong khi TTS đang kế thừa nó**: TTS phải nhận key mới ngay, không giữ bản sao cũ. Ràng buộc này loại bỏ cách làm "copy key lúc khởi tạo `Translator`" — phải đọc theo tham chiếu tại thời điểm dùng.
- **Migration khi user đã sửa tay `config.json`**: file hiện có `speechModels` với giá trị `edge-tts/...`. Sau khi thêm khái niệm provider, các giá trị này phải tiếp tục được hiểu là thuộc provider `api`.

### Technical Risks

- **Hợp đồng `Data` là ràng buộc cứng, cũng là điểm mạnh**: toàn bộ `speechCache`, `SpeechTrim.bounds`, `AVAudioPlayer(data:)`, `attachAudio` đều giả định một blob audio hoàn chỉnh. Nhánh native **phải** tôn trọng hợp đồng này. Rủi ro thấp nếu tuân thủ, rất cao nếu ai đó cố stream.
- **`AVSpeechSynthesizer.write` cần run loop sống**: chặn thread chờ callback sẽ deadlock. Đã gặp trực tiếp khi benchmark (script treo quá 300 s). App là AppKit nên có run loop, nhưng đường async phải viết đúng.
- **Dung lượng history**: 3.261 KB cho một câu 348 ký tự. Không encode thì history phình rất nhanh. Đây là rủi ro dữ liệu, không chỉ hiệu năng.
- **Bề mặt thay đổi của `SpeechIdentity`**: nó là khóa Dictionary, tham số của 7+ hàm, và có mặt trong test. Thêm field vào nó là thay đổi lan rộng nhất của cả yêu cầu này. `SpeechModelResolver.model` có 7 nơi gọi trên 3 file, kèm test.
- **Keychain nhiều entry**: `APIKeyStore.shared` là singleton với service/account cố định. Chuyển sang nhiều scope cần đổi cách khởi tạo ở cả hai nơi dựng `Translator`. Rủi ro: di trú sai thì user mất key và không hiểu tại sao app ngừng chạy.
- **Chất lượng giọng tiếng Việt native là bước lùi**: `vi-VN.Linh` compact so với `vi-VN-HoaiMyNeural`. Rủi ro trải nghiệm, không phải rủi ro kỹ thuật, nhưng chạm đúng ngôn ngữ chính của user.
- **Không chạy được `swift test`**: theo `CLAUDE.md`, target test dùng swift-testing mà toolchain hiện tại không có. Việc kiểm chứng phải dựa vào `swift build` cộng kiểm thử thủ công, nên các thay đổi lan rộng như `SpeechIdentity` mất đi lưới an toàn.
- **Foundation Models không có cam kết ổn định về output**: ngay cả tình huống proofread đang pass cũng không có gì bảo đảm giữ nguyên qua các bản macOS. Đây là lý do nữa để không đặt tính năng cốt lõi lên nó.

### Acceptance Criteria Coverage

Yêu cầu được phát biểu dưới dạng bốn gạch đầu dòng, không phải AC hình thức. Bảng dưới đánh giá từng gạch như một AC.

| AC# | Description | Addressable? | Gaps/Notes |
|-----|-------------|--------------|------------|
| 1 | Tách riêng API key + URL cho LLM và TTS | Yes | URL đã tách sẵn ở tầng config nhưng còn ghép qua `derivedSpeechURL`. Key tách bằng một entry Keychain tùy chọn, kế thừa key LLM khi trống (D2) — không cần di trú. Ràng buộc: key phải đọc tại thời điểm dùng, không sao chép lúc khởi tạo. |
| 2 | Setting TTS chọn native macOS hoặc API; nếu API thì nhập key + URL | Yes | Hợp đồng `Data` đã đúng sẵn nên tầng dưới không đổi. Còn mở: cách chọn voice native cho từng ngôn ngữ. Bắt buộc kèm: encode audio native trước khi lưu history, và `SpeechIdentity` mang provider. |
| 3 | retryButton clear cache audio | Yes (phạm vi đã chốt) | Phạm vi = bản ghi đang xem, cả RAM lẫn history của riêng nó (D3). Ba khoảng trống phải bịt: `invalidateSpeech` hiện **không** xóa `speechCache`/`speechTrim`; `hydrateStoredAudio` nạp lại audio cũ từ history; `retrySubRequest` không gọi `invalidateSpeech` chút nào. Một hàm dùng chung cho cả ba, gọi thêm từ lúc lưu setting TTS. |
| 4 | Đánh giá Apple Intelligence, nếu dùng được thì cho chọn làm LLM provider | **Closed — không triển khai** | Đã test: translate trả nguyên văn không dịch và sai nghĩa khi ép dịch; learn fail cứng vì `learnPrompt` chiếm 4091/4096 token; rò system prompt ra output. Chỉ proofread pass. Điều kiện "nếu xài được" không thỏa mãn. User chốt bỏ hẳn (D1). Phần đánh giá của AC này **đã hoàn thành**; phần triển khai **có chủ đích không làm**. |

**Vùng phủ**: 3/4 AC sẵn sàng cho REASONS Canvas; AC4 đóng lại với kết luận không triển khai. Sau khi chốt D1, toàn bộ phạm vi code còn lại nằm ở TTS và credential — tầng LLM không đổi ngoài việc `Translator` thôi kiêm nhiệm TTS.
