Attribute VB_Name = "FXBlotter"
Option Explicit

'=====================================================================
' FX Blotter 자동 변환 매크로
'
' 사용법:
'   1) SetupWorkbook 매크로를 1회 실행 (Paste/Blotter/Holidays 시트 생성)
'   2) 이메일/메신저에서 거래 내역을 드래그-복사
'   3) Paste 시트 A1에 붙여넣기
'   4) [변환 →] 버튼 클릭
'   → Blotter 시트 맨 아래에 Value / KRW / USD 행이 건별로 추가됨
'   → 구분 코드와 Customer Rate은 수동 입력 (Rate 입력 시 반대 통화 자동 계산)
'
' 포맷 파서 구조 (고객사별 포맷 추가 가능):
'   ParseLine()이 등록된 파서를 순서대로 시도하고, 모두 실패하면
'   TryGeneric() 휴리스틱이 추정 파싱 후 노란색으로 표시(수동 확인용).
'   새 고객 포맷 추가 방법은 README.md의 "새 포맷 추가" 섹션 참고.
'
'   등록된 파서:
'     TryUbsFxOrderList     : "11-Jun-26 BUY KRW 2,439,375,000.00 Sell USD No Round"
'     TryUbsFxRequest       : "Sell KRW 872,000,000 USD 20260611"
'     TryUbsStockSettlement : 주식 결제내역 (ISIN KR+숫자10자리 토큰 기준)
'     TryGeneric            : 미등록 포맷 폴백 (날짜+BUY/SELL+통화+금액 탐색)
'
' 부호 규칙: 고객이 "매수"하는 통화 = 음수(-), 반대 통화 = 양수(+)
'   - 주식 BUY      → 고객이 결제 대금 KRW 매수 → KRW 음수
'   - 주식 SELL     → 고객이 KRW 매도            → KRW 양수
'   - "BUY KRW"     → KRW 음수 / "SELL KRW" → KRW 양수
'   - USD 금액만 있는 거래도 동일 논리로 USD 쪽에 부호
'
' Value 판정: 오늘 날짜 기준 영업일 계산 (주말 + Holidays 시트의 공휴일 제외)
'   밸류데이트 = 오늘      → TDY
'   밸류데이트 = 익영업일  → TOM
'   밸류데이트 = 2영업일 후 → SPOT
'   그 외                  → 날짜 그대로 표기 (수동 확인 필요)
'=====================================================================

'----- 시트/컬럼 설정: 실제 통합문서 구성에 맞게 여기만 수정 -----
Private Const SHEET_PASTE As String = "Paste"
Private Const SHEET_BLOTTER As String = "Blotter"
Private Const SHEET_HOLIDAYS As String = "Holidays"

Private Const COL_GUBUN As Long = 1     ' 구분 코드 — 인식된 포맷명이 미리 채워지며, 실제 코드로 덮어쓰면 됨
Private Const COL_VALUE As Long = 2     ' Value (TDY/TOM/SPOT)
Private Const COL_KRW As Long = 3       ' KRW 금액
Private Const COL_USD As Long = 4       ' USD 금액
Private Const COL_CRATE As Long = 5     ' Customer Rate (수동 입력)
Private Const COL_IRATE As Long = 6     ' Interbank Rate (수동 입력)
Private Const BLOTTER_HEADER_ROW As Long = 1

' 변환 후 Paste 시트를 비울지 여부
Private Const CLEAR_PASTE_AFTER As Boolean = True

'=====================================================================
' 메인: Paste 시트 → Blotter 시트
'=====================================================================
Public Sub ConvertPaste()
    Dim wsP As Worksheet, wsB As Worksheet
    Set wsP = GetSheet(SHEET_PASTE)
    Set wsB = GetSheet(SHEET_BLOTTER)
    If wsP Is Nothing Or wsB Is Nothing Then
        MsgBox "'" & SHEET_PASTE & "' / '" & SHEET_BLOTTER & "' 시트가 없습니다." & vbCrLf & _
               "SetupWorkbook 매크로를 먼저 실행하세요.", vbExclamation
        Exit Sub
    End If

    Dim lines As Collection
    Set lines = ReadPasteLines(wsP)
    If lines.Count = 0 Then
        MsgBox "'" & SHEET_PASTE & "' 시트에 붙여넣은 내용이 없습니다.", vbExclamation
        Exit Sub
    End If

    ' 라인별 파싱: 각 레코드 = Array(밸류데이트, 통화, 부호 적용된 금액, 포맷명)
    Dim recs As New Collection
    Dim ln As Variant, rec As Variant
    Dim skipped As Long, generic As Long
    For Each ln In lines
        rec = ParseLine(CStr(ln))
        If IsArray(rec) Then
            recs.Add rec
            If rec(3) = "GENERIC" Then generic = generic + 1
        Else
            skipped = skipped + 1
        End If
    Next ln

    If recs.Count = 0 Then
        MsgBox "인식 가능한 거래 라인이 없습니다." & vbCrLf & _
               "(헤더·서명 등 " & skipped & "줄은 무시되었습니다)" & vbCrLf & vbCrLf & _
               "새로운 고객 포맷이라면 README의 '새 포맷 추가'를 참고해 파서를 등록하세요.", vbExclamation
        Exit Sub
    End If

    Dim r As Long
    r = LastBlotterRow(wsB) + 1
    Dim added As Long
    For Each rec In recs
        WriteRecord wsB, r, rec
        r = r + 1
        added = added + 1
    Next rec

    If CLEAR_PASTE_AFTER Then wsP.UsedRange.ClearContents

    Dim msg As String
    msg = added & "건이 '" & SHEET_BLOTTER & "' 시트에 추가되었습니다." & vbCrLf & vbCrLf & _
          "▶ 구분 칸의 포맷명을 실제 구분 코드로 바꾸고 Customer Rate을 입력하세요." & vbCrLf & _
          "▶ Rate 입력 시 반대 통화 금액이 자동 계산됩니다."
    If generic > 0 Then
        msg = msg & vbCrLf & vbCrLf & "⚠ 미등록 포맷 " & generic & "건을 추정 파싱했습니다 (노란색 표시)." & vbCrLf & _
              "   금액·부호·날짜를 반드시 확인하세요!"
    End If
    If skipped > 0 Then msg = msg & vbCrLf & "(헤더·서명 등 " & skipped & "줄 무시됨)"
    MsgBox msg, IIf(generic > 0, vbExclamation, vbInformation)
End Sub

'=====================================================================
' 1회 실행: 시트 + 버튼 준비
'=====================================================================
Public Sub SetupWorkbook()
    Dim ws As Worksheet

    Set ws = EnsureSheet(SHEET_BLOTTER)
    If Trim$(CStr(ws.Cells(BLOTTER_HEADER_ROW, COL_GUBUN).Value)) = "" Then
        ws.Cells(BLOTTER_HEADER_ROW, COL_GUBUN).Value = "구분"
        ws.Cells(BLOTTER_HEADER_ROW, COL_VALUE).Value = "Value"
        ws.Cells(BLOTTER_HEADER_ROW, COL_KRW).Value = "KRW"
        ws.Cells(BLOTTER_HEADER_ROW, COL_USD).Value = "USD"
        ws.Cells(BLOTTER_HEADER_ROW, COL_CRATE).Value = "Customer Rate"
        ws.Cells(BLOTTER_HEADER_ROW, COL_IRATE).Value = "Interbank Rate"
        ws.Rows(BLOTTER_HEADER_ROW).Font.Bold = True
    End If

    Set ws = EnsureSheet(SHEET_HOLIDAYS)
    If Trim$(CStr(ws.Cells(1, 1).Value)) = "" Then
        ws.Cells(1, 1).Value = "한국 공휴일 목록 (A2부터 날짜 입력, 예: 2026-08-15)"
        ws.Cells(1, 1).Font.Bold = True
        ws.Columns(1).ColumnWidth = 40
    End If

    Set ws = EnsureSheet(SHEET_PASTE)
    AddConvertButton ws

    MsgBox "준비 완료!" & vbCrLf & vbCrLf & _
           "1) '" & SHEET_HOLIDAYS & "' 시트에 공휴일을 입력해 두세요." & vbCrLf & _
           "2) '" & SHEET_PASTE & "' 시트 A1에 내역을 붙여넣고 [변환 →] 버튼을 누르세요.", vbInformation
End Sub

'=====================================================================
' 파서 디스패처
'   새 고객 포맷을 추가하려면 TryXxx 함수를 만들고 아래에 한 줄 추가.
'   구체적인 파서일수록 위에, TryGeneric은 반드시 마지막에 둘 것.
'=====================================================================
Private Function ParseLine(ByVal raw As String) As Variant
    Dim s As String
    s = NormalizeSpaces(raw)
    If Len(s) = 0 Then Exit Function

    Dim t() As String
    t = Split(s, " ")

    Dim rec As Variant
    rec = TryUbsFxOrderList(t)
    If Not IsArray(rec) Then rec = TryUbsFxRequest(t)
    If Not IsArray(rec) Then rec = TryUbsStockSettlement(t)
    ' --- 새 고객사 파서는 여기에 추가 ---
    If Not IsArray(rec) Then rec = TryGeneric(t)
    ParseLine = rec
End Function

'=====================================================================
' UBS 포맷 파서
'=====================================================================

' [UBS FX 주문 리스트] "11-Jun-26 BUY KRW 2,439,375,000.00 Sell USD No Round"
Private Function TryUbsFxOrderList(t() As String) As Variant
    If UBound(t) < 3 Then Exit Function
    Dim vd As Date
    If Not TryParseDate(t(0), vd) Then Exit Function
    Dim side As String: side = UCase$(t(1))
    If side <> "BUY" And side <> "SELL" Then Exit Function
    Dim ccy As String: ccy = UCase$(t(2))
    If ccy <> "KRW" And ccy <> "USD" Then Exit Function
    Dim amt As Double
    If Not TryParseNum(t(3), amt) Then Exit Function
    If side = "BUY" Then amt = -amt          ' 고객 매수 통화 = 음수
    TryUbsFxOrderList = Array(vd, ccy, amt, "UBS-FXLIST")
End Function

' [UBS FX 단건 요청] "Sell KRW 872,000,000 USD 20260611"  (밸류데이트는 뒤쪽 토큰에서 탐색)
Private Function TryUbsFxRequest(t() As String) As Variant
    If UBound(t) < 3 Then Exit Function
    Dim side As String: side = UCase$(t(0))
    If side <> "BUY" And side <> "SELL" Then Exit Function
    Dim ccy As String: ccy = UCase$(t(1))
    If ccy <> "KRW" And ccy <> "USD" Then Exit Function
    Dim amt As Double
    If Not TryParseNum(t(2), amt) Then Exit Function

    Dim vd As Date, i As Long, found As Boolean
    For i = UBound(t) To 3 Step -1
        If TryParseDate(t(i), vd) Then found = True: Exit For
    Next i
    If Not found Then Exit Function

    If side = "BUY" Then amt = -amt          ' 고객 매수 통화 = 음수
    TryUbsFxRequest = Array(vd, ccy, amt, "UBS-FXREQ")
End Function

' [UBS 주식 결제내역] ISIN(KR + 숫자 10자리) 토큰을 기준점으로 파싱
'   ... <Trade Ref> <ISIN> <종목코드> <B/S> <수량> KRW <단가> ... KRW <결제금액> SETTLEMENT ...
'   밸류데이트 = Settlement Date (라인 앞 4~6번째 토큰 "12 Jun 2026")
Private Function TryUbsStockSettlement(t() As String) As Variant
    If UBound(t) < 10 Then Exit Function

    Dim i As Long, isinIdx As Long: isinIdx = -1
    For i = 0 To UBound(t)
        If Len(t(i)) = 12 And UCase$(Left$(t(i), 2)) = "KR" And IsAllDigits(Mid$(t(i), 3)) Then
            isinIdx = i
            Exit For
        End If
    Next i
    If isinIdx = -1 Or isinIdx + 3 > UBound(t) Then Exit Function

    Dim side As String: side = UCase$(t(isinIdx + 2))
    If side <> "BUY" And side <> "SELL" Then Exit Function

    ' B/S 이후 두 번째 "KRW" 다음 토큰 = Settlement Amount
    Dim k As Long, krwCount As Long, amtIdx As Long: amtIdx = -1
    For k = isinIdx + 3 To UBound(t)
        If UCase$(t(k)) = "KRW" Then
            krwCount = krwCount + 1
            If krwCount = 2 Then amtIdx = k + 1: Exit For
        End If
    Next k
    If amtIdx = -1 Or amtIdx > UBound(t) Then Exit Function

    Dim amt As Double
    If Not TryParseNum(t(amtIdx), amt) Then Exit Function

    ' Settlement Date = 토큰 3~5 ("12 Jun 2026")
    Dim vd As Date
    If Not TryParseEngDate3(t(3), t(4), t(5), vd) Then Exit Function

    ' 주식 BUY → 고객이 결제 대금 KRW 매수 → KRW 음수 / SELL → 양수
    If side = "BUY" Then amt = -amt
    TryUbsStockSettlement = Array(vd, "KRW", amt, "UBS-STOCK")
End Function

'=====================================================================
' 미등록 포맷 폴백 (휴리스틱)
'   조건: 라인에 (1) 날짜, (2) BUY/SELL 토큰, (3) 통화 토큰 + 바로 뒤 숫자가
'   모두 있으면 추정 파싱. 결과는 노란색으로 표시되어 수동 확인 필요.
'   부호는 등록 파서와 동일: BUY = 해당 통화 매수 = 음수.
'=====================================================================
Private Function TryGeneric(t() As String) As Variant
    If UBound(t) < 3 Then Exit Function

    ' (1) 날짜: 단일 토큰 형식 우선, 없으면 "12 Jun 2026" 3토큰 형식
    Dim i As Long, vd As Date, hasDate As Boolean
    For i = 0 To UBound(t)
        If TryParseDate(t(i), vd) Then hasDate = True: Exit For
    Next i
    If Not hasDate Then
        For i = 0 To UBound(t) - 2
            If TryParseEngDate3(t(i), t(i + 1), t(i + 2), vd) Then hasDate = True: Exit For
        Next i
    End If
    If Not hasDate Then Exit Function

    ' (2) 첫 번째 BUY/SELL 토큰
    Dim sideIdx As Long: sideIdx = -1
    For i = 0 To UBound(t)
        If UCase$(t(i)) = "BUY" Or UCase$(t(i)) = "SELL" Then sideIdx = i: Exit For
    Next i
    If sideIdx = -1 Then Exit Function
    Dim side As String: side = UCase$(t(sideIdx))

    ' (3) side 이후 가장 가까운 [통화 + 숫자] 쌍, 없으면 라인 전체에서 탐색
    Dim ccy As String, amt As Double, found As Boolean
    For i = sideIdx + 1 To UBound(t) - 1
        If IsCcy(t(i)) Then
            If TryParseNum(t(i + 1), amt) Then ccy = UCase$(t(i)): found = True: Exit For
        End If
    Next i
    If Not found Then
        For i = 0 To UBound(t) - 1
            If IsCcy(t(i)) Then
                If TryParseNum(t(i + 1), amt) Then ccy = UCase$(t(i)): found = True: Exit For
            End If
        Next i
    End If
    If Not found Then Exit Function

    If side = "BUY" Then amt = -amt          ' 고객 매수 통화 = 음수
    TryGeneric = Array(vd, ccy, amt, "GENERIC")
End Function

Private Function IsCcy(ByVal s As String) As Boolean
    s = UCase$(Trim$(s))
    IsCcy = (s = "KRW" Or s = "USD")
End Function

'=====================================================================
' Blotter 기록
'=====================================================================
Private Sub WriteRecord(ws As Worksheet, ByVal r As Long, rec As Variant)
    Dim vd As Date: vd = rec(0)
    Dim ccy As String: ccy = CStr(rec(1))
    Dim amt As Double: amt = rec(2)
    Dim fmt As String: fmt = CStr(rec(3))

    Dim rateAddr As String, krwAddr As String, usdAddr As String
    rateAddr = ws.Cells(r, COL_CRATE).Address(False, False)
    krwAddr = ws.Cells(r, COL_KRW).Address(False, False)
    usdAddr = ws.Cells(r, COL_USD).Address(False, False)

    ws.Cells(r, COL_VALUE).Value = ValueLabel(vd)

    If ccy = "KRW" Then
        ws.Cells(r, COL_KRW).Value = amt
        ' Customer Rate 입력 시 USD = -KRW / Rate (부호 자동 반전)
        ws.Cells(r, COL_USD).Formula = _
            "=IF(" & rateAddr & "="""","""",ROUND(-" & krwAddr & "/" & rateAddr & ",2))"
    Else
        ws.Cells(r, COL_USD).Value = amt
        ' Customer Rate 입력 시 KRW = -USD * Rate (부호 자동 반전)
        ws.Cells(r, COL_KRW).Formula = _
            "=IF(" & rateAddr & "="""","""",ROUND(-" & usdAddr & "*" & rateAddr & ",0))"
    End If

    ws.Cells(r, COL_KRW).NumberFormat = "#,##0.00"
    ws.Cells(r, COL_USD).NumberFormat = "#,##0.00"
    ws.Cells(r, COL_CRATE).NumberFormat = "#,##0.00"

    ' 구분 칸에 인식된 포맷명을 미리 채움 → 실제 구분 코드로 덮어쓰면 됨
    ws.Cells(r, COL_GUBUN).Value = fmt

    ' 미등록 포맷 추정 결과는 노란색으로 표시 → 수동 확인
    If fmt = "GENERIC" Then
        ws.Range(ws.Cells(r, COL_VALUE), ws.Cells(r, COL_USD)).Interior.Color = vbYellow
    End If
End Sub

Private Function LastBlotterRow(ws As Worksheet) As Long
    Dim c As Long, last As Long, v As Long
    last = BLOTTER_HEADER_ROW
    For c = COL_GUBUN To COL_IRATE
        v = ws.Cells(ws.Rows.Count, c).End(xlUp).Row
        If v > last Then last = v
    Next c
    LastBlotterRow = last
End Function

'=====================================================================
' Value 판정 (영업일 계산)
'=====================================================================
Private Function ValueLabel(ByVal vd As Date) As String
    Dim tdy As Date: tdy = Date
    If vd = tdy Then
        ValueLabel = "TDY"
    ElseIf vd = AddBizDays(tdy, 1) Then
        ValueLabel = "TOM"
    ElseIf vd = AddBizDays(tdy, 2) Then
        ValueLabel = "SPOT"
    Else
        ' TDY/TOM/SPOT 범위 밖 → 날짜 그대로 표기해서 수동 확인 유도
        ValueLabel = Format$(vd, "dd-mmm-yy")
    End If
End Function

Private Function AddBizDays(ByVal d As Date, ByVal n As Long) As Date
    Dim c As Long
    Do While c < n
        d = d + 1
        If Weekday(d, vbMonday) <= 5 And Not IsHoliday(d) Then c = c + 1
    Loop
    AddBizDays = d
End Function

Private Function IsHoliday(ByVal d As Date) As Boolean
    Dim ws As Worksheet
    Set ws = GetSheet(SHEET_HOLIDAYS)
    If ws Is Nothing Then Exit Function
    Dim lastR As Long, i As Long
    lastR = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    For i = 1 To lastR
        If IsDate(ws.Cells(i, 1).Value) Then
            If CDate(ws.Cells(i, 1).Value) = d Then
                IsHoliday = True
                Exit Function
            End If
        End If
    Next i
End Function

'=====================================================================
' Paste 시트 읽기 / 문자열 유틸
'=====================================================================
Private Function ReadPasteLines(ws As Worksheet) As Collection
    Dim out As New Collection
    Dim ur As Range
    Set ur = ws.UsedRange
    Dim rIdx As Long, cIdx As Long
    Dim s As String, v As Variant, tok As String
    For rIdx = 1 To ur.Rows.Count
        s = ""
        For cIdx = 1 To ur.Columns.Count
            v = ur.Cells(rIdx, cIdx).Value
            If Not IsEmpty(v) And Not IsError(v) Then
                ' 붙여넣기 중 날짜로 자동 변환된 셀도 파싱 가능하게 통일
                If VarType(v) = vbDate Then
                    tok = Format$(v, "yyyymmdd")
                Else
                    tok = CStr(v)
                End If
                If Len(Trim$(tok)) > 0 Then s = s & " " & tok
            End If
        Next cIdx
        s = Trim$(s)
        If Len(s) > 0 Then out.Add s
    Next rIdx
    Set ReadPasteLines = out
End Function

Private Function NormalizeSpaces(ByVal s As String) As String
    s = Replace(s, vbTab, " ")
    s = Replace(s, Chr$(160), " ")   ' non-breaking space
    s = Replace(s, vbCr, " ")
    s = Replace(s, vbLf, " ")
    Do While InStr(s, "  ") > 0
        s = Replace(s, "  ", " ")
    Loop
    NormalizeSpaces = Trim$(s)
End Function

Private Function TryParseNum(ByVal s As String, ByRef v As Double) As Boolean
    s = Replace(Trim$(s), ",", "")
    If Len(s) = 0 Then Exit Function
    Dim i As Long, hasDigit As Boolean
    For i = 1 To Len(s)
        Select Case Mid$(s, i, 1)
            Case "0" To "9": hasDigit = True
            Case ".", "-"
            Case Else: Exit Function
        End Select
    Next i
    If Not hasDigit Then Exit Function
    v = Val(s)
    TryParseNum = True
End Function

' 지원 날짜 형식: yyyymmdd / dd-Mmm-yy / dd-Mmm-yyyy / yyyy-mm-dd
Private Function TryParseDate(ByVal s As String, ByRef d As Date) As Boolean
    s = Trim$(s)
    On Error GoTo fail

    If Len(s) = 8 And IsAllDigits(s) Then
        d = DateSerial(CLng(Left$(s, 4)), CLng(Mid$(s, 5, 2)), CLng(Right$(s, 2)))
        TryParseDate = True
        Exit Function
    End If

    Dim p() As String
    p = Split(s, "-")
    If UBound(p) = 2 Then
        If Len(p(0)) = 4 And IsAllDigits(p(0)) And IsAllDigits(p(1)) And IsAllDigits(p(2)) Then
            ' yyyy-mm-dd
            d = DateSerial(CLng(p(0)), CLng(p(1)), CLng(p(2)))
            TryParseDate = True
            Exit Function
        End If
        Dim m As Long
        m = MonthFromEng(p(1))
        If m > 0 And IsAllDigits(p(0)) And IsAllDigits(p(2)) Then
            ' dd-Mmm-yy / dd-Mmm-yyyy
            Dim y As Long: y = CLng(p(2))
            If y < 100 Then y = y + 2000
            d = DateSerial(y, m, CLng(p(0)))
            TryParseDate = True
            Exit Function
        End If
    End If
fail:
End Function

' "12" "Jun" "2026" 형태 (영문 월 이름, 로캘 무관)
Private Function TryParseEngDate3(ByVal dd As String, ByVal mmm As String, ByVal yyyy As String, ByRef d As Date) As Boolean
    On Error GoTo fail
    Dim m As Long
    m = MonthFromEng(mmm)
    If m = 0 Or Not IsAllDigits(dd) Or Not IsAllDigits(yyyy) Then Exit Function
    If Len(yyyy) <> 4 Then Exit Function
    d = DateSerial(CLng(yyyy), m, CLng(dd))
    TryParseEngDate3 = True
fail:
End Function

Private Function MonthFromEng(ByVal s As String) As Long
    Select Case UCase$(Left$(Trim$(s), 3))
        Case "JAN": MonthFromEng = 1
        Case "FEB": MonthFromEng = 2
        Case "MAR": MonthFromEng = 3
        Case "APR": MonthFromEng = 4
        Case "MAY": MonthFromEng = 5
        Case "JUN": MonthFromEng = 6
        Case "JUL": MonthFromEng = 7
        Case "AUG": MonthFromEng = 8
        Case "SEP": MonthFromEng = 9
        Case "OCT": MonthFromEng = 10
        Case "NOV": MonthFromEng = 11
        Case "DEC": MonthFromEng = 12
    End Select
End Function

Private Function IsAllDigits(ByVal s As String) As Boolean
    If Len(s) = 0 Then Exit Function
    Dim i As Long
    For i = 1 To Len(s)
        If Mid$(s, i, 1) < "0" Or Mid$(s, i, 1) > "9" Then Exit Function
    Next i
    IsAllDigits = True
End Function

'=====================================================================
' 시트/버튼 유틸
'=====================================================================
Private Function GetSheet(ByVal name As String) As Worksheet
    On Error Resume Next
    Set GetSheet = ThisWorkbook.Worksheets(name)
    On Error GoTo 0
End Function

Private Function EnsureSheet(ByVal name As String) As Worksheet
    Dim ws As Worksheet
    Set ws = GetSheet(name)
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        ws.Name = name
    End If
    Set EnsureSheet = ws
End Function

Private Sub AddConvertButton(ws As Worksheet)
    Dim b As Button
    On Error Resume Next
    ws.Buttons("btnConvert").Delete
    On Error GoTo 0
    Set b = ws.Buttons.Add(ws.Columns(8).Left + 10, 10, 110, 32)
    b.Name = "btnConvert"
    b.Caption = "변환 →"
    b.OnAction = "ConvertPaste"
End Sub
