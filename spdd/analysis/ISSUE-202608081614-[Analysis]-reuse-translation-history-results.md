# SPDD Analysis: Tái sử dụng kết quả Translate, Learn và audio từ history

## Original Business Requirement

tối ưu bước mở popup translate, nếu text có dịch trước đó (history) thì tái sử dụng; đồng thời cùng 1 text + ngôn ngữ đã dịch trong history rồi thì cũng tái sử dụng (tái sử dụng luôn audio nếu có); tóm lại unique theo ngôn ngữ + text, nếu đã dịch trước đó thì tải sử dụng lại để không cần phải call TTS và call LLM lại, áp dụng luôn cho cả nút 'Learn' ('Learn' và 'Translate' lưu thành 2 dòng history, nếu bấm 'Learn' mà có trước đó rồi thì tái sử dụng, tương tự cho 'Translate')

## Domain Concept Identification

### Existing Concepts (from codebase)

- **Translation request**: Gửi text cùng cặp ngôn ngữ đến LLM cho luồng Translate — kết quả thành công hiện tạo một bản ghi history mới.
- **Learn request**: Gửi cùng text và cặp ngôn ngữ đến LLM với prompt học từ hoặc câu — kết quả hiện chỉ hiển thị trong popup, chưa được lưu history.
- **Translation history**: Lưu các bản ghi theo thứ tự mới nhất trong `history.json`; mỗi bản ghi chứa source text, result text, source language, target language, trạng thái Saved và tham chiếu audio — hiện chỉ định danh duy nhất bằng ID ngẫu nhiên, chưa có quy tắc duy nhất theo nội dung.
- **Translation record**: Đại diện một lần Translate đã hoàn tất — hiện chưa phân biệt loại kết quả Translate hay Learn.
- **Language pair**: Kết hợp source language và target language đã resolve cho request — ảnh hưởng trực tiếp đến ý nghĩa và khả năng tái sử dụng kết quả.
- **Resolved source language**: Ngôn ngữ nguồn thực tế của kết quả Translate khi dùng Auto detect — được lưu vào history và dùng nhất quán cho nhãn cùng source TTS.
- **Persistent audio**: Audio source/result gắn với một bản ghi history và lưu thành file riêng — có thể đọc lại nếu file vẫn tồn tại.
- **Speech identity và in-memory speech cache**: Định danh audio theo loại source/result, text, speech model và record ID — tránh gọi TTS lặp trong vòng đời tiến trình nhưng chưa tự khôi phục audio từ history khi mở lại popup.
- **Popup translation lifecycle**: Mở popup từ selection, resolve ngôn ngữ, bắt đầu request bất đồng bộ, hiển thị kết quả, lưu history và prefetch speech — có generation guard để kết quả cũ không ghi đè request mới.

### New Concepts Required

- **Result mode**: Phân biệt rõ kết quả `Translate` và `Learn` trong history — cùng text và cặp ngôn ngữ phải có thể tồn tại thành hai dòng với nội dung, vòng đời tái sử dụng độc lập.
- **History reuse identity**: Danh tính nghiệp vụ ổn định của kết quả, tối thiểu gồm mode, source text và cặp ngôn ngữ đã resolve — dùng để xác định bản ghi phù hợp thay vì ID theo từng lần gọi.
- **Reusable history result**: Bản ghi history đủ điều kiện cấp lại result text và audio hiện có cho popup mà không gọi LLM hoặc TTS.
- **Reuse outcome**: Trạng thái cache hit hoặc cache miss trong luồng popup — cache hit đi thẳng đến hiển thị và phát/prefetch audio; cache miss giữ nguyên luồng dịch, lưu và gắn audio hiện tại.

### Key Business Rules

- Cùng mode, cùng source text và cùng cặp ngôn ngữ phải tái sử dụng bản ghi history phù hợp thay vì gọi lại LLM.
- `Translate` và `Learn` là hai mode độc lập; cùng text và ngôn ngữ phải lưu được hai dòng history và không tái sử dụng chéo kết quả.
- Mở popup Translate phải kiểm tra history trước khi bắt đầu LLM; bấm Translate hoặc Learn cũng áp dụng cùng quy tắc cho mode tương ứng.
- Cache hit phải dùng lại result text đã lưu và giữ đúng source/target language của bản ghi.
- Audio chỉ được tái sử dụng khi file còn tồn tại và phù hợp với text cùng speech model đang cần; thiếu hoặc lỗi audio không được làm mất khả năng tái sử dụng result text.
- Cache hit có audio hợp lệ không được gọi TTS lại; cache hit thiếu audio chỉ gọi TTS khi chính sách hiện tại yêu cầu prefetch hoặc người dùng bấm phát.
- Cache miss tạo đúng một dòng history cho identity nghiệp vụ đó; thao tác lặp lại không được tiếp tục sinh bản ghi trùng.
- Generation guard và trạng thái request hiện có vẫn phải ngăn kết quả cũ cập nhật popup sau khi input, mode hoặc ngôn ngữ đã đổi.
- History hỏng hoặc bị khóa không được âm thầm ghi đè dữ liệu; luồng fallback cần giữ nguyên bảo vệ dữ liệu hiện tại.

## Strategic Approach

### Solution Direction

- Dùng `TranslationHistoryStore` hiện có làm nguồn cache bền vững, không tạo cache hoặc kho dữ liệu thứ hai. Mở rộng ý nghĩa bản ghi để phân biệt Translate/Learn và tra cứu theo history reuse identity.
- Đặt quyết định cache hit trước ranh giới gọi LLM trong luồng popup. Cache hit nạp result, resolved language, record identity và audio sẵn có vào state hiện tại; cache miss đi qua Translator rồi lưu như hiện nay.
- Đưa Learn vào cùng vòng đời history như Translate: kết quả thành công được lưu theo mode Learn, có current record riêng và hưởng cùng cơ chế audio/reuse.
- Giữ audio file gắn với bản ghi history làm nguồn bền vững; in-memory speech cache chỉ là lớp tăng tốc trong phiên và được nạp từ audio của bản ghi cache hit.
- Không đổi endpoint LLM/TTS, không thêm dependency và không đưa image translation hoặc image search vào phạm vi khi yêu cầu chỉ nói text Translate/Learn.

### Key Design Decisions

- **Khóa duy nhất phải gồm mode**: Cụm “unique theo ngôn ngữ + text” xung đột với yêu cầu Translate và Learn thành hai dòng. Chỉ dùng ngôn ngữ + text sẽ làm hai mode va chạm. Khuyến nghị mode + normalized identity của text + source language + target language để thỏa cả hai ý.
- **Source language trong identity**: Chỉ target language không đủ vì cùng text có thể được xử lý dưới source language khác, kể cả grammar-check khi source bằng target. Khuyến nghị dùng cả cặp ngôn ngữ đã resolve.
- **Tái sử dụng bản ghi thay vì append lần truy cập mới**: Append mỗi cache hit giữ nhật ký thao tác nhưng phá quy tắc không trùng và nhân đôi audio. Khuyến nghị trả lại bản ghi hiện có; chỉ tạo hai dòng độc lập cho hai mode.
- **History là cache duy nhất**: Một cache riêng có thể tra nhanh hơn nhưng tạo hai nguồn chân lý, migration và invalidation. Khuyến nghị tra cứu trên records đang nạp sẵn; chỉ cân nhắc index khi lịch sử đo được đủ lớn để gây chậm popup.
- **Audio compatibility**: Audio phụ thuộc text và speech model, trong khi history hiện chỉ lưu path. Khuyến nghị chỉ tái sử dụng khi có đủ bằng chứng tương thích; nếu cấu hình voice/model đổi mà metadata không chứng minh tương thích, ưu tiên tạo audio mới thay vì phát sai giọng.
- **Cache hit không làm mới nội dung LLM**: Tái sử dụng tối đa chi phí đồng nghĩa prompt/model/config mới không tự làm mất hiệu lực kết quả cũ. Khuyến nghị chấp nhận semantics này cho yêu cầu hiện tại, nhưng cần xác nhận nếu người dùng mong kết quả tự refresh sau đổi cấu hình.
- **Text matching**: Exact text bảo toàn ngữ nghĩa và tránh cache hit sai; normalize quá mạnh có thể hợp nhất input người dùng xem là khác. Khuyến nghị chỉ dùng chuẩn hóa tối thiểu, nhất quán với input mà popup đã gửi, cho đến khi có quy tắc sản phẩm rõ hơn.

### Alternatives Considered

- **Chỉ dùng in-memory cache**: Loại vì không tái sử dụng qua lần khởi động app và không tận dụng audio bền vững trong history.
- **Tái sử dụng kết quả mới nhất chỉ theo source text**: Loại vì sai khi target language, source language hoặc mode khác.
- **Dùng chung một dòng cho Translate và Learn**: Loại vì kết quả khác loại và yêu cầu rõ hai dòng history.
- **Luôn nhân bản bản ghi cache hit thành dòng mới**: Loại vì tạo duplicate, tăng storage và làm ownership audio khó rõ ràng.
- **Gọi LLM rồi so sánh history sau**: Loại vì không đạt mục tiêu giảm độ trễ và chi phí LLM.
- **Luôn gọi TTS nếu speech model hiện tại khác**: Có thể đúng về giọng nhưng bỏ mục tiêu tái sử dụng audio; chỉ nên áp dụng khi compatibility metadata cho thấy audio cũ không phù hợp.

## Risk & Gap Analysis

### Requirement Ambiguities

- **Định nghĩa “ngôn ngữ + text”**: Chưa rõ gồm target language בלבד hay cả source và target; cần xác nhận cặp ngôn ngữ là identity an toàn hơn.
- **Mode không được nêu trong cụm unique**: Yêu cầu hai dòng Translate/Learn bắt buộc mode tham gia identity dù câu tóm tắt chỉ nói ngôn ngữ + text.
- **Chuẩn hóa text**: Chưa rõ phân biệt hoa/thường, khoảng trắng đầu cuối, nhiều khoảng trắng, Unicode normalization và xuống dòng.
- **Thời điểm lưu Learn**: Chưa nêu Learn có đầy đủ Saved, source/result audio và hành vi mở lại từ History như Translate hay chỉ cần dòng để cache.
- **Tái sử dụng audio sau đổi voice/model**: Chưa rõ audio cũ có được dùng bất kể speech model hiện tại hay phải tạo lại khi cấu hình đổi.
- **Hiệu lực cache khi prompt/model đổi**: Chưa rõ kết quả history cũ có tiếp tục hợp lệ vô thời hạn hay cần phiên bản hóa theo cấu hình LLM.
- **Timestamp trên cache hit**: Chưa rõ bản ghi cũ có được đưa lên đầu history hoặc cập nhật thời gian truy cập hay giữ nguyên thời điểm tạo.
- **Duplicate lịch sử đã tồn tại**: Chưa rõ chọn bản ghi mới nhất, bản ghi có audio đầy đủ nhất, hay cần dọn duplicate cũ.
- **Auto detect lookup**: Trước request, source language chính xác có thể chưa được LLM xác nhận; cần làm rõ identity dùng lựa chọn `Auto detect`, local resolved language hay source language đã lưu.

### Edge Cases

- **Cùng text, khác mode**: Phải tạo và tái sử dụng hai kết quả độc lập, không lấy bản dịch làm nội dung Learn hoặc ngược lại.
- **Cùng text, khác target language**: Không được cache hit chéo ngôn ngữ.
- **Cùng text, source bằng target**: Translate là grammar-check; không được dùng kết quả dịch từ cặp khác.
- **Auto detect cho text giống nhau**: Local resolution và source language history có thể khác sau thay đổi detector hoặc model; lookup phải có semantics ổn định.
- **Bản ghi có result nhưng thiếu audio**: Vẫn tái sử dụng LLM result; TTS chỉ chạy khi cần.
- **Audio path tồn tại nhưng file mất/hỏng**: Không gọi LLM lại; xử lý như audio cache miss.
- **Một trong source/result audio tồn tại**: Tái sử dụng từng audio độc lập, chỉ tạo phần thiếu khi cần.
- **Nhiều duplicate cũ cùng identity**: Chọn bản ghi phải deterministic và không làm mất Saved/audio hữu ích.
- **Người dùng xóa bản ghi đang mở**: Popup không được giữ tham chiếu audio/history không còn hợp lệ.
- **Cache hit trong lúc request cũ còn chạy**: Kết quả cũ không được ghi thêm history hoặc ghi đè nội dung cache hit mới.
- **History load error**: Không được sửa hoặc overwrite file hỏng; cần fallback LLM mà không phá dữ liệu hoặc báo trạng thái phù hợp.
- **Input rất dài**: Tra cứu history không được làm giảm bảo vệ `maxTranslateLength` hiện tại.
- **Image input**: Không có source text tương đương rõ ràng; nằm ngoài phạm vi cache này.

### Technical Risks

- **Thiếu mode trong schema hiện tại**: Không thể phân biệt an toàn bản ghi Translate và Learn cũ. Hướng giảm thiểu: định nghĩa backward compatibility rõ, coi bản ghi cũ là Translate trừ khi có bằng chứng khác.
- **Audio thiếu metadata model**: `SpeechIdentity` có model nhưng persistent record không lưu model. Có thể tái sử dụng sai voice sau đổi cấu hình. Hướng giảm thiểu: xác lập compatibility policy hoặc bổ sung identity bền vững cần thiết trong REASONS Canvas.
- **Lookup Auto detect trước LLM**: Source language lưu trong history là resolved language, còn request mới bắt đầu bằng Auto detect/local resolution. Có thể miss hợp lệ hoặc hit sai. Hướng giảm thiểu: chọn một canonical language identity dùng nhất quán cho lookup và persist.
- **Toàn vẹn uniqueness**: Store hiện là JSON array trong memory, không có DB constraint; các request gần nhau có thể cùng miss rồi append duplicate. Hướng giảm thiểu: tập trung lookup và write trong store chạy trên MainActor, đồng thời giữ generation checks.
- **Chi phí quét history**: Lookup tuyến tính trên records đã nạp là hướng nhỏ nhất nhưng tăng theo lịch sử. Hướng giảm thiểu: đo trước; chỉ thêm index khi thời gian mở popup bị ảnh hưởng thực tế.
- **Duplicate và audio ownership**: Dọn hoặc gộp duplicate có thể xóa file audio còn được dùng. Hướng giảm thiểu: không migration phá hủy trong phạm vi đầu; chọn record deterministic và tách kế hoạch cleanup nếu cần.
- **Cache stale theo prompt/model**: Learn prompt hoặc translation model đổi nhưng identity nghiệp vụ không đổi. Hướng giảm thiểu: xác nhận sản phẩm ưu tiên tiết kiệm hay freshness trước khi thiết kế invalidation.
- **Khoảng trống test tích hợp**: Store có test persistence/audio, nhưng luồng popup Translate/Learn, cache hit và việc không gọi network chưa có coverage trực tiếp. Hướng giảm thiểu: thiết kế seam kiểm chứng nhỏ quanh quyết định reuse và giữ test store cho identity/audio.

### Acceptance Criteria Coverage

Yêu cầu không cung cấp danh sách AC riêng. Các mệnh đề nghiệp vụ được chuyển thành AC tạm thời để kiểm tra độ phủ.

| AC# | Description | Addressable? | Gaps/Notes |
|---|---|---|---|
| 1 | Khi mở popup Translate với text và cặp ngôn ngữ đã có trong history, hiển thị lại kết quả mà không gọi LLM. | Partial | Cần chốt identity cho Auto detect và chuẩn hóa text. |
| 2 | Cache hit tái sử dụng audio hiện có và không gọi TTS lại. | Partial | Cần chốt compatibility khi speech model/voice đổi và hành vi với file hỏng. |
| 3 | Cùng text và ngôn ngữ không tiếp tục tạo các dòng history trùng cho cùng mode. | Yes | Store hiện chưa có uniqueness; quy tắc chọn duplicate cũ vẫn cần chốt. |
| 4 | Translate và Learn lưu thành hai dòng history riêng. | Partial | Schema hiện thiếu mode; cần chốt backward compatibility và History UI có hiển thị mode hay không. |
| 5 | Bấm Learn với identity đã có thì dùng lại Learn result và audio, không gọi LLM/TTS lại. | Partial | Learn hiện chưa lưu history hoặc audio; cần chốt phạm vi audio của Learn. |
| 6 | Bấm Translate với identity đã có thì dùng lại Translate result và audio, không gọi LLM/TTS lại. | Partial | Cần chốt timestamp/cache-hit behavior và Auto detect matching. |
| 7 | Cache miss vẫn gọi dịch, lưu kết quả và audio theo hành vi hiện tại. | Yes | Learn cần được đưa vào vòng đời persist tương đương Translate. |
| 8 | Cache hit hoặc stale async completion không làm sai state popup, language, history hay audio. | Yes | Có generation guard hiện hữu; cần áp dụng cùng invariant cho nhánh reuse. |
