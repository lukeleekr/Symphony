# FX Blotter 자동 변환 (Excel VBA)

이메일·메신저로 오는 거래 내역(주식 결제내역, FX 요청, FX 주문 리스트)을
**복사 → 붙여넣기 → 버튼 클릭** 만으로 FX 블로터 시트에
`Value / KRW / USD` 행으로 자동 정리해 주는 Excel 매크로입니다.

## 동작 흐름

```
이메일/메신저에서 드래그-복사
        ↓
[Paste 시트] A1에 붙여넣기
        ↓
[변환 →] 버튼 클릭  ← 포맷 자동 감지 (아래 3종)
        ↓
[Blotter 시트] 맨 아래에 건별로 행 추가
   구분(수동) | Value(자동) | KRW(자동) | USD(자동수식) | Customer Rate(수동) | Interbank Rate(수동)
        ↓
구분 코드 + Customer Rate 입력 → 반대 통화 금액 자동 계산
```

## 지원 입력 포맷 (자동 감지)

파서는 **레지스트리 구조**입니다 — 등록된 고객사별 파서를 순서대로 시도하고,
모두 실패하면 Generic 폴백이 추정 파싱합니다. 현재 등록된 파서:

| 파서 | 대상 | 예시 | 인식 기준 |
|---|---|---|---|
| `TryUbsStockSettlement` | UBS 주식 결제내역 | `10 Jun 2026 12 Jun 2026 ... KR7012630000 012630.KS BUY 21,654 KRW ...` | ISIN(`KR`+숫자 10자리) 토큰 |
| `TryUbsFxRequest` | UBS FX 단건 요청 | `Sell KRW 872,000,000 USD 20260611` | `Buy/Sell` + 통화로 시작, 뒤에 `yyyymmdd` 밸류데이트 |
| `TryUbsFxOrderList` | UBS FX 주문 리스트 | `11-Jun-26 BUY KRW 2,439,375,000.00 Sell USD No Round` | `dd-Mmm-yy` 날짜로 시작 |
| `TryGeneric` | **미등록 포맷 폴백** | 날짜 + `BUY/SELL` + 통화 + 금액이 있는 모든 줄 | 휴리스틱 추정 → **노란색 표시** |

- 헤더 줄, 서명, 결제지시문 등 거래가 아닌 줄은 자동으로 무시됩니다.
- Generic 폴백으로 파싱된 행은 **노란색으로 표시**되며, 금액·부호·날짜를 반드시 수동 확인해야 합니다.
- `Blotter` 시트의 `Src(자동)` 컬럼에 어떤 파서가 인식했는지 기록됩니다 (감사·디버깅용, `COL_SRC = 0`으로 끌 수 있음).

## 새 포맷 추가 (다른 고객사 대응)

현재 3개 파서는 UBS 포맷 전용입니다. 다른 고객사 포맷이 자주 오면 전용 파서를 등록하세요:

1. `FXBlotter.bas`에 `TryXxx` 함수 추가 — 토큰 배열을 받아 인식 실패 시 그냥 `Exit Function`,
   성공 시 `Array(밸류데이트, 통화, 부호적용금액, "포맷이름")` 반환:

   ```vb
   ' [예: ABC은행 FX 컨펌] "ABC FX CONF 20260615 CLIENT BUYS USD 1,000,000.00"
   Private Function TryAbcBankFx(t() As String) As Variant
       If UBound(t) < 7 Then Exit Function
       If UCase$(t(0)) <> "ABC" Or UCase$(t(1)) <> "FX" Then Exit Function   ' 포맷 식별 앵커
       Dim vd As Date
       If Not TryParseDate(t(3), vd) Then Exit Function
       Dim amt As Double
       If Not TryParseNum(t(7), amt) Then Exit Function
       If UCase$(t(5)) = "BUYS" Then amt = -amt        ' 고객 매수 통화 = 음수
       TryAbcBankFx = Array(vd, UCase$(t(6)), amt, "ABC-FX")
   End Function
   ```

2. `ParseLine`의 디스패처에 한 줄 추가 (TryGeneric **앞에**):

   ```vb
   If Not IsArray(rec) Then rec = TryAbcBankFx(t)
   ' --- 새 고객사 파서는 여기에 추가 ---
   If Not IsArray(rec) Then rec = TryGeneric(t)
   ```

파서 작성 팁:
- 그 포맷에만 있는 **고유한 앵커**(고정 키워드, 참조번호 패턴, ISIN 등)로 먼저 식별하고 나머지를 파싱하면 오인식이 없습니다.
- 공용 유틸을 재사용하세요: `TryParseDate`(yyyymmdd / dd-Mmm-yy / yyyy-mm-dd), `TryParseEngDate3`("12 Jun 2026"), `TryParseNum`(콤마 포함 숫자).
- 부호 규칙은 항상 동일: **고객이 매수하는 통화 = 음수**.
- 새 포맷이 어떤 모습인지 모를 때는 일단 붙여넣어 보세요 — Generic 폴백이 잡으면 노란색 행으로 들어오고, `Src` 컬럼에 `GENERIC`이 찍힙니다. 그 결과가 자주 틀리면 전용 파서를 만들 시점입니다.

## 변환 규칙

### 부호 (고객 관점)
**고객이 매수하는 통화 = 음수(−), 반대 통화 = 양수(+)**

| 입력 | KRW | USD |
|---|---|---|
| 주식 BUY (고객이 결제 대금 KRW 매수) | − Settlement Amount | + (자동계산) |
| 주식 SELL | + Settlement Amount | − (자동계산) |
| `BUY KRW` | − 금액 | + (자동계산) |
| `SELL KRW` | + 금액 | − (자동계산) |
| `BUY USD` (USD 금액만 있는 경우) | + (자동계산) | − 금액 |

### 금액·날짜 소스
- **포맷①**: 금액 = Settlement Amount, 밸류데이트 = Settlement Date
- **포맷②③**: 표기된 금액·밸류데이트 그대로

### Value 컬럼 (TDY / TOM / SPOT)
오늘 날짜 기준 **영업일** 계산 (주말 + `Holidays` 시트의 공휴일 제외):

| 밸류데이트 | 표기 |
|---|---|
| 오늘 | `TDY` |
| 익영업일 (T+1) | `TOM` |
| 2영업일 후 (T+2) | `SPOT` |
| 그 외 | 날짜 그대로 (`15-Jun-26`) — 수동 확인 필요 |

### 반대 통화 자동 계산
매크로가 반대 통화 셀에 수식을 넣어 둡니다. Customer Rate을 입력하는 순간 계산됩니다.

- KRW가 원본 금액일 때: `USD = ROUND(-KRW / CustomerRate, 2)`
- USD가 원본 금액일 때: `KRW = ROUND(-USD × CustomerRate, 0)`

## 설치 (1회)

1. 블로터 엑셀 파일을 열고 `Alt + F11` (VBA 편집기)
2. 메뉴 **File → Import File...** → `FXBlotter.bas` 선택
3. `Alt + F11`로 돌아와서 `Alt + F8` → `SetupWorkbook` 실행
   → `Paste` / `Blotter` / `Holidays` 시트와 [변환 →] 버튼이 생성됩니다
4. **다른 이름으로 저장 → 파일 형식: Excel 매크로 사용 통합 문서(*.xlsm)**
5. `Holidays` 시트 A열에 한국 공휴일을 입력해 두세요 (예: `2026-08-15`) — 연 1회 업데이트

> 기존 블로터 시트를 그대로 쓰려면: `FXBlotter.bas` 상단의
> `SHEET_BLOTTER`, `COL_VALUE`, `COL_KRW` 등 상수만 실제 시트명/컬럼 번호에 맞게 수정하면 됩니다.

## 사용법 (매일)

1. 이메일/메신저에서 내역을 드래그-복사
2. `Paste` 시트 A1 클릭 → 붙여넣기 (`Ctrl+V`)
3. [변환 →] 버튼 클릭
4. `Blotter` 시트에서 **구분 코드**와 **Customer Rate** 입력
   → 반대 통화 금액 자동 계산 완료

여러 포맷을 한 번에 붙여넣어도 됩니다 (줄 단위로 각각 인식).

## 샘플 데이터

`samples/` 폴더에 포맷별 테스트 입력이 있습니다.
**전부 가공된 더미 데이터**입니다 — 실제 고객명·계좌번호·거래 데이터는 절대 이 저장소에 커밋하지 마세요.

| 파일 | 내용 |
|---|---|
| `samples/format1_stock_settlement.txt` | 주식 결제내역 (BUY/SELL 각 1건) |
| `samples/format2_fx_request.txt` | FX 단건 요청 |
| `samples/format3_fx_orders.txt` | FX 주문 리스트 (BUY/SELL 혼합) |

## 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| "인식 가능한 거래 라인이 없습니다" | Generic 폴백조차 인식 못 한 새 포맷 → 위 "새 포맷 추가" 참고 |
| 노란색 행이 추가됨 | 미등록 포맷을 Generic 폴백이 추정 파싱한 것 → 금액·부호·날짜 수동 확인. 자주 오는 포맷이면 전용 파서 등록 권장 |
| Value가 `TDY/TOM/SPOT`이 아닌 날짜로 표기됨 | 밸류데이트가 T~T+2 범위 밖 (포워드 등) → 수동 확인용 의도된 동작. 공휴일 누락 시 `Holidays` 시트 확인 |
| 금액이 이상한 행이 섞임 | 원본 복사 시 줄바꿈이 깨졌을 가능성 → 한 거래 = 한 줄로 붙여넣어졌는지 Paste 시트에서 확인 |
| 매크로 실행 안 됨 | 파일이 `.xlsm`인지, 보안 경고에서 "콘텐츠 사용"을 눌렀는지 확인 |
