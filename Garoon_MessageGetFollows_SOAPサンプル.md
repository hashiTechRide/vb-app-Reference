# VB.NET Garoon SOAP API - MessageGetFollows サンプル(生SOAP方式)

## 概要

- 対象: Garoon **パッケージ版(オンプレミス)**
- 認証: **Basic認証**(ログイン名/パスワード)
- 実装方式: Web参照を使わず、`HttpWebRequest`でSOAPエンベロープを直接組み立てて送信する方式
- 対象API: `MessageGetFollowsMulti`(メッセージのフォロー一覧取得)

---

## 前提・注意点

- Garoonのバージョンによって、メソッド名(`MessageGetFollows` / `MessageGetFollowsMulti`)やXMLスキーマが異なる場合があります。実際のWSDL(`?MessageCgi;jp;WSDL`などのURL)で正確なスキーマを確認してください。
- エンドポイントのパス(`grn.exe`部分)は環境によってカスタマイズされていることがあります。
- 複数メッセージIDを指定する場合は`<message_id>`を複数並べる形式になることが多いです。

---

## サンプルコード

```vb.net
Imports System.Net
Imports System.Text
Imports System.IO
Imports System.Xml

Module GaroonMessageGetFollows

    ' ==== 環境に応じて書き換えてください ====
    Private Const GaroonBaseUrl As String = "http://<your-garoon-server>/cgi-bin/cbgrn/grn.exe"
    Private Const LoginName As String = "your_login_id"
    Private Const Password As String = "your_password"
    Private Const MessageId As String = "12345" ' 対象メッセージID

    Sub Main()
        Try
            Dim responseXml As String = CallMessageGetFollows(MessageId)
            Console.WriteLine(responseXml)

            ParseFollows(responseXml)
        Catch ex As Exception
            Console.WriteLine("エラー: " & ex.Message)
        End Try

        Console.ReadLine()
    End Sub

    ''' <summary>
    ''' MessageGetFollows APIを呼び出す
    ''' </summary>
    Function CallMessageGetFollows(msgId As String) As String

        ' SOAPエンベロープを構築
        Dim soapEnvelope As String = $"
<?xml version=""1.0"" encoding=""UTF-8""?>
<soap:Envelope xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/""
               xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema"">
  <soap:Header>
    <Action xmlns=""http://schemas.cybozu.co.jp/soap/action""
            SOAP-ENV:mustUnderstand=""1""
            xmlns:SOAP-ENV=""http://schemas.xmlsoap.org/soap/envelope/"">MessageGetFollowsMulti</Action>
    <Security xmlns=""http://schemas.xmlsoap.org/ws/2002/12/secext"">
      <UsernameToken>
        <Username>{LoginName}</Username>
        <Password>{Password}</Password>
      </UsernameToken>
    </Security>
    <Locale xmlns=""http://schemas.cybozu.co.jp/soap/locale"">ja</Locale>
    <Timezone xmlns=""http://schemas.cybozu.co.jp/soap/base"">Asia/Tokyo</Timezone>
  </soap:Header>
  <soap:Body>
    <MessageGetFollowsMulti xmlns=""http://schemas.cybozu.co.jp/schema/message"">
      <message_id>{msgId}</message_id>
    </MessageGetFollowsMulti>
  </soap:Body>
</soap:Envelope>".Trim()

        Dim endpoint As String = GaroonBaseUrl & "?MessageCgi;jp"

        Dim req As HttpWebRequest = CType(WebRequest.Create(endpoint), HttpWebRequest)
        req.Method = "POST"
        req.ContentType = "text/xml; charset=UTF-8"
        req.Headers.Add("SOAPAction", """MessageGetFollowsMulti""")

        ' ---- Basic認証 ----
        Dim credBytes As Byte() = Encoding.UTF8.GetBytes(LoginName & ":" & Password)
        req.Headers.Add("Authorization", "Basic " & Convert.ToBase64String(credBytes))

        Dim bodyBytes As Byte() = Encoding.UTF8.GetBytes(soapEnvelope)
        req.ContentLength = bodyBytes.Length

        Using reqStream As Stream = req.GetRequestStream()
            reqStream.Write(bodyBytes, 0, bodyBytes.Length)
        End Using

        Try
            Using resp As HttpWebResponse = CType(req.GetResponse(), HttpWebResponse)
                Using respStream As Stream = resp.GetResponseStream()
                    Using reader As New StreamReader(respStream, Encoding.UTF8)
                        Return reader.ReadToEnd()
                    End Using
                End Using
            End Using
        Catch wex As WebException
            ' Garoonはエラー時もSOAP Faultをボディに返すことが多いので中身を読む
            If wex.Response IsNot Nothing Then
                Using respStream As Stream = wex.Response.GetResponseStream()
                    Using reader As New StreamReader(respStream, Encoding.UTF8)
                        Dim errBody As String = reader.ReadToEnd()
                        Throw New Exception("SOAP Fault: " & errBody, wex)
                    End Using
                End Using
            End If
            Throw
        End Try
    End Function

    ''' <summary>
    ''' レスポンスXMLをパースしてフォロー一覧を表示
    ''' </summary>
    Sub ParseFollows(xml As String)
        Dim doc As New XmlDocument()
        doc.LoadXml(xml)

        Dim nsmgr As New XmlNamespaceManager(doc.NameTable)
        nsmgr.AddNamespace("soap", "http://schemas.xmlsoap.org/soap/envelope/")
        nsmgr.AddNamespace("m", "http://schemas.cybozu.co.jp/schema/message")

        Dim followNodes As XmlNodeList = doc.SelectNodes("//m:follow", nsmgr)

        If followNodes Is Nothing OrElse followNodes.Count = 0 Then
            Console.WriteLine("フォローが見つかりませんでした。")
            Return
        End If

        For Each node As XmlNode In followNodes
            Dim followId As String = node.Attributes("id")?.Value
            Dim creator As String = node.SelectSingleNode("m:creator", nsmgr)?.Attributes("name")?.Value
            Dim dateTime As String = node.SelectSingleNode("m:datetime", nsmgr)?.InnerText
            Dim content As String = node.SelectSingleNode("m:content", nsmgr)?.InnerText

            Console.WriteLine($"[{followId}] {creator} ({dateTime})")
            Console.WriteLine(content)
            Console.WriteLine("---")
        Next
    End Sub

End Module
```

---

## 補足・注意点(再掲)

### 実機に合わせて調整が必要な箇所

- `MessageGetFollowsMulti` vs `MessageGetFollows`: Garoonのバージョンによってメソッド名や複数ID対応の仕様が異なります。実際のWSDLに合わせてXML構造を調整してください。
- `MessageId`の複数指定が必要な場合、`<message_id>`を複数並べる形式になることが多いです。
- パッケージ版ではエンドポイントのパス(`grn.exe`部分)がカスタマイズされている場合があるため、実際のWSDL URLに合わせてください。

### 動作確認の進め方

1. まずWSDL(`?MessageCgi;jp;WSDL`のようなURL)をブラウザで取得し、`MessageGetFollows`系メソッドの正確な入出力スキーマを確認する
2. SoapUIなどのツールで一度動作するリクエストを作ってから、VB.NETコードのXML構造をそれに合わせる
3. `wex.Response`からのエラーボディ取得部分でSOAP Faultの中身を必ず確認する(認証エラーかスキーマエラーか切り分けやすくなります)


Web参照方式でのFault確認方法と、よくある原因を整理します。

## 1. SOAP Faultの中身を見る方法

Web参照(自動生成プロキシ)経由だと、エラーは`System.Web.Services.Protocols.SoapException`として飛んできます。これをキャッチして中身を出力してください。

```vb.net
Try
    Dim client As New MessageBinding()
    client.Credentials = New NetworkCredential(LoginName, Password)
    client.PreAuthenticate = True

    Dim request As New MessageGetFollowRequestType()
    request.message_id = "12345"

    Dim response = client.MessageGetFollow(request)

Catch soapEx As System.Web.Services.Protocols.SoapException
    ' ここが本命。Garoonが返してきた本当のエラー内容
    Console.WriteLine("=== SOAP Fault ===")
    Console.WriteLine("Code: " & soapEx.Code.ToString())
    Console.WriteLine("Message: " & soapEx.Message)
    Console.WriteLine("Detail: " & soapEx.Detail?.OuterXml)
    Console.WriteLine("Actor: " & soapEx.Actor)

Catch ex As Exception
    Console.WriteLine("その他エラー: " & ex.Message)
End Try
```

`soapEx.Detail.OuterXml`がGaroon側の詳しいエラーコード・メッセージを含んでいることが多いです。ここが一番重要な情報なので、まずこれを出力してみてください。

## 2. 送信している実際のXMLも見る(推奨)

Web参照経由だと何を送っているか見えづらいので、`SoapExtension`を使わずに簡易的に確認するなら、`Fiddler`や`Wireshark`などのHTTPキャプチャツールを使うか、以下のようにプロキシクラスに軽くトレースを仕込む方法があります。

```vb.net
' プロキシクラスの継承元は System.Web.Services.Protocols.SoapHttpClientProtocol
' 簡易的に確認したいだけなら、まずはFault Detailの中身を見るのが手軽です
```

もし可能であれば、Fiddlerなどでリクエスト/レスポンスの生XMLをキャプチャするのが一番確実です(パッケージ版はローカルネットワーク内通信のことが多いのでFiddlerでも捕捉しやすいはずです)。

## 3. 「他のメソッドは動くのにこれだけ失敗する」場合のよくある原因

| 原因 | 具体例 |
|---|---|
| **必須プロパティの未設定** | `message_id`以外に`message_type`や`confirmation_type`など、GaroonのMessageGetFollows系は地味に必須パラメータが多いです |
| **型の不一致** | `message_id`がプロキシ上は`String()`(配列)なのに`String`単体を代入している(またはその逆) |
| **メソッド名違い** | `MessageGetFollow`ではなく実際は`MessageGetFollows`(複数形)や`MessageGetFollowConfirmation`など、似た名前の別メソッドを呼んでいる |
| **SOAPヘッダー未設定** | `Action`ヘッダーや`Locale`/`Timezone`ヘッダーをプロキシが自動生成していない/正しく設定されていない |

`MessageGetFollowRequestType`のプロパティを一通り確認したいので、Visual Studioで以下を教えてもらえますか。

- `MessageGetFollowRequestType`にインテリセンスで出てくる**プロパティ一覧**(`message_id`以外に何があるか)
- `soapEx.Detail.OuterXml`(または`soapEx.Message`)の出力内容

これが分かれば、不正の原因をかなり絞り込めます。


VB.NET/.NET Framework 4.8での実装ですね。設計の考え方も含めて回答します。

## 設計方針

**責務は分けた方がいい**です。理由は：

- 「行単位の検証・エラー書き込み」と「エラー列名の集計・表示」は目的が違う
- 後で検証ロジックだけ再利用したい場面（保存前チェックのみ、UI通知なし等）が出やすい
- テストしやすい

というわけで、以下のような構成をお勧めします。

```vb
' 1つの検証結果を表す小さな構造体
Public Structure ValidationError
    Public Property ColumnName As String
    Public Property Message As String
End Structure

Public Class DataTableValidator

    ''' <summary>
    ''' DataTableを検証し、各行のRowErrorとエラー列にエラー情報を設定する。
    ''' エラーがあった列名のセットを返す（呼び出し側でメッセージ表示に使う）。
    ''' </summary>
    Public Function ValidateAndMarkErrors(dt As DataTable) As HashSet(Of String)
        Dim errorColumns As New HashSet(Of String)()

        For Each row As DataRow In dt.Rows
            If row.RowState = DataRowState.Deleted Then Continue For

            Dim rowErrors As New List(Of ValidationError)()

            ' --- 個別の検証ロジック ---
            rowErrors.AddRange(ValidateRow(row))

            ' --- 行への反映 ---
            If rowErrors.Count > 0 Then
                For Each err In rowErrors
                    row.SetColumnError(err.ColumnName, err.Message)
                    errorColumns.Add(err.ColumnName)
                Next
                row.RowError = String.Join(vbCrLf, rowErrors.Select(Function(e) e.Message))
            Else
                row.ClearErrors()
            End If
        Next

        Return errorColumns
    End Function

    ''' <summary>1行分の検証ルールをまとめる</summary>
    Private Function ValidateRow(row As DataRow) As List(Of ValidationError)
        Dim errors As New List(Of ValidationError)()

        If row.IsNull("商品コード") OrElse CStr(row("商品コード")) = "" Then
            errors.Add(New ValidationError With {
                .ColumnName = "商品コード",
                .Message = "商品コードが未入力です。"
            })
        End If

        If Not row.IsNull("数量") Then
            Dim qty As Decimal
            If Decimal.TryParse(row("数量").ToString(), qty) Then
                If qty < 0 Then
                    errors.Add(New ValidationError With {
                        .ColumnName = "数量",
                        .Message = "数量は0以上で入力してください。"
                    })
                End If
            Else
                errors.Add(New ValidationError With {
                    .ColumnName = "数量",
                    .Message = "数量が数値ではありません。"
                })
            End If
        End If

        Return errors
    End Function

End Class
```

## 呼び出し側（表示担当）

```vb
Dim validator As New DataTableValidator()
Dim errorColumns = validator.ValidateAndMarkErrors(dt)

If errorColumns.Count > 0 Then
    MessageBox.Show(
        "以下の列にエラーがあります:" & vbCrLf & String.Join(vbCrLf, errorColumns),
        "入力エラー",
        MessageBoxButtons.OK,
        MessageBoxIcon.Warning)
Else
    MessageBox.Show("エラーはありませんでした。")
End If
```

## ポイント

- `SetColumnError` / `RowError` を使うと、DataGridView・C1FlexGridなどのバインドグリッドで自動的にエラーアイコンが出せます（お使いのC1FlexGridでも対応しているはずです）
- 検証メソッド（`ValidateAndMarkErrors`）は**戻り値でエラー列名を返すだけ**にして、メッセージ表示はしない
- 表示は呼び出し元（フォームやプレゼンター）でやる — MVVM的にもこちらが自然です

同じメソッド内で書くこと自体は動きますが、上記のように分けておくと「保存前は検証だけ実行してダイアログは出さない」といった変更にも柔軟に対応できます。


これは典型的な問題で、Oracleの制約の遅延（DEFERRABLE）が本命の解決策です。ただし制約定義の変更が必要なので、それが可能かどうかで選択肢が変わります。順に整理します。

## 何が起きているか

行ごとにUPDATEを分割していると、途中の中間状態でユニーク制約に引っかかります。

```
初期: 行A = 'X', 行B = 'Y'    （X,Y をスワップしたい）

UPDATE 行A SET key='Y'  ← この瞬間、行A='Y' と 行B='Y' が衝突 → ORA-00001
UPDATE 行B SET key='X'  ← ここまで到達できない
```

Oracleの**非遅延（IMMEDIATE）制約は、各DML文の終了時点でチェック**します。だから文を分けると、途中の一時的な重複が許されません。

## 解決策1：制約をDEFERRABLEにする（本命）

制約を遅延可能に定義し、トランザクション内で遅延させれば、**COMMIT時点でだけチェック**されます。中間状態の重複が許され、スワップがそのまま通ります。

### 制約の定義変更

```sql
-- 既存制約を落として、DEFERRABLE で作り直す
ALTER TABLE BASE_TABLE DROP CONSTRAINT UK_BASE_KEY;

ALTER TABLE BASE_TABLE
  ADD CONSTRAINT UK_BASE_KEY UNIQUE (FACTORY_CODE, ITEM_CODE, TARGET_DATE)
  DEFERRABLE INITIALLY IMMEDIATE;
```

`DEFERRABLE INITIALLY IMMEDIATE` にしておくと、普段は今まで通り即時チェック、必要なときだけセッションで遅延に切り替えられます。`INITIALLY DEFERRED` にすると常に遅延になりますが、既存処理の挙動が変わるので `INITIALLY IMMEDIATE` が無難です。

### 遅延させる（スワップするトランザクションだけ）

```vb
Using tx = conn.BeginTransaction()
    ' このトランザクションだけ制約を遅延
    ExecuteNonQuery(conn, tx, "SET CONSTRAINT UK_BASE_KEY DEFERRED")

    ' 行ごとのUPDATE群（中間状態で重複してもOK）
    For Each item In changes
        ExecUpdate(conn, tx, item)
    Next

    tx.Commit()   ← ここで初めて制約チェック。最終状態が正しければ通る
End Using
```

すべての制約を遅延したいなら `SET CONSTRAINTS ALL DEFERRED` も使えます。

### 注意点

制約違反はCOMMIT時に出るので、**例外の発生箇所が変わります**。個々のUPDATEでなくCommitで`ORA-02091`（トランザクションのロールバック）＋`ORA-00001`が返るため、エラーハンドリングをCommit周りにも用意してください。どの行が原因かは分かりにくくなるので、前回話した**事前チェック（複数列INでの重複検出）をより重要視**することになります。

一意インデックスは**非ユニークインデックスに変わる**点も押さえてください。DEFERRABLEな一意制約は、内部的に非ユニークインデックスで実装されます。これまでのユニークインデックス前提の実行計画が変わる可能性があるので、検証環境で性能を確認しておくと安全です（前回の一括重複チェックは非ユニークインデックスでも十分効きます）。

## 解決策2：一時的な退避値を使う（制約を変えられない場合）

制約定義を変更できないなら、衝突しない一時値を経由する古典的な手です。3ステップになります。

```sql
-- ① 片方を絶対に衝突しない一時値へ退避
UPDATE BASE_TABLE SET KEY_COL = :tempValue WHERE SEQ = :seqA;
-- ② もう片方を目的の値へ
UPDATE BASE_TABLE SET KEY_COL = :valueFromA WHERE SEQ = :seqB;
-- ③ 退避した行を目的の値へ
UPDATE BASE_TABLE SET KEY_COL = :valueFromB WHERE SEQ = :seqA;
```

一時値は他と絶対に衝突しないものを選ぶ必要があります（負のシーケンス値、GUID、業務上あり得ないプレフィックス付き文字列など）。ただし複合キーだと一時値の作り方が難しく、また処理が煩雑になります。スワップが2行だけならまだしも、複数行が循環的に入れ替わる場合は退避が入り組んで扱いにくい。

## 解決策3：1文のMERGEにまとめる

行ごとの分割UPDATEをやめ、**1つのDML文で全行を更新**すれば、文の終了時点では最終状態になっているので中間状態の重複が発生しません。

```sql
MERGE INTO BASE_TABLE b
USING (
    SELECT :seq0 AS SEQ, :key0 AS KEY_COL FROM DUAL
    UNION ALL SELECT :seq1, :key1 FROM DUAL
    UNION ALL SELECT :seq2, :key2 FROM DUAL
) src
ON (b.SEQ = src.SEQ)
WHEN MATCHED THEN UPDATE SET b.KEY_COL = src.KEY_COL
```

1文で完結するので、文終了時に一括チェックされ、スワップも通ります。ただし**Oracleは文の途中でも一意制約を検出する場合があり、行の処理順によっては引っかかることがある**ため、これは確実な方法ではありません。実際に検証が必要です。DEFERRABLEのほうが確実です。

前回の議論で出た**グローバル一時表にキーを投入してMERGE**する形なら、UNION ALLの冗長さも避けられます。

## 解決策4：削除してから挿入する

該当行を一度DELETEしてから、新しい値でINSERTし直す方法。DELETEで既存値が消えるので衝突しません。ただし主キーやSeq、他テーブルからの外部キー参照、更新日時などの扱いが面倒になり、履歴やトリガーがあると副作用が出ます。既存Seqを保ちたい今回のような設計には向きません。

## 推奨

**解決策1（DEFERRABLE）が本命**です。理由は、スワップに限らず「複数行の相互依存的な更新」全般に効き、行ごとの分割UPDATEという現在の実装をそのまま活かせるからです。退避値やMERGEへの作り替えは、実装を歪めるか確実性に欠けます。

制約を`DEFERRABLE INITIALLY IMMEDIATE`にしておけば、普段の挙動は変わらず、スワップが起きうる保存処理でだけ`SET CONSTRAINT ... DEFERRED`を宣言すればよい。影響範囲が限定的です。

## 前回までの設計との接続

前回、保存前に複数列INで重複を事前チェックする話をしました。DEFERRABLEにすると制約違反がCommit時に出て原因行が特定しにくくなるので、**事前チェックの価値がさらに上がります**。

```
1. アプリ内で編集行同士の重複チェック（スワップは重複ではないので通る）
2. DBに複数列INで既存重複チェック（自分の編集行は除外）
3. 保存トランザクション：SET CONSTRAINT DEFERRED → 行ごとUPDATE → Commit
4. Commit時の制約違反は最終防衛として捕捉（原因はエラー列に反映しきれないので全体エラー扱い）
```

事前チェックで「最終状態に重複がないか」を確認しておけば、Commit時の違反はほぼ競合（他者が同時更新）だけになります。

ここで一点注意があります。**スワップは事前チェックで重複と誤判定されやすい**です。編集行同士のチェックで「A→Y, B→X」と最終状態を見れば重複しませんが、DB既存との照合で「Yは既にB行に存在する」と判定してしまう。既存照合のとき、**編集対象の行（自分たちのSeq群）を除外する**のを忘れないでください。前回の`SEQ NOT IN (:editingSeqs)`がまさにこれです。スワップ対象の両方のSeqを除外リストに入れれば、誤検出しません。

## まとめ

- 原因は、Oracleの非遅延制約が**各DML文の終了時にチェック**するため、行ごとに分割したUPDATEの中間状態で重複が発生すること。
- **本命はDEFERRABLE制約**。`DEFERRABLE INITIALLY IMMEDIATE`で作り直し、スワップが起きる保存トランザクションで`SET CONSTRAINT ... DEFERRED`を宣言すれば、**COMMIT時にだけチェック**され中間状態の重複が許される。現在の分割UPDATE実装をそのまま活かせる。
- 注意点は2つ。**違反がCommit時に出るのでエラーハンドリング位置が変わる**こと、**一意インデックスが非ユニークインデックスになる**ので実行計画を検証すること。
- 制約を変更できないなら、**一時的な退避値を経由する3段階UPDATE**。ただし複合キーや循環スワップだと煩雑。
- **1文のMERGEにまとめる**手もあるが、Oracleが文の途中で検出する場合があり確実ではない。
- 事前チェックとの関係で重要な点：**既存重複チェックのとき編集対象のSeq群を除外**しないと、スワップを重複と誤判定する（`SEQ NOT IN (:editingSeqs)`）。
- DEFERRABLEにすると原因行の特定が難しくなるので、**事前チェックの重要性が上がる**。Commit時の違反はほぼ競合のみ、という状態を目指す。

まずは制約定義を変更できるか（本番テーブルにALTERをかけられるか）を確認してください。可能なら解決策1が最もきれいで、スワップ以外の相互依存更新にも効きます。変更できない事情があるなら、退避値方式に落とすことになります。
