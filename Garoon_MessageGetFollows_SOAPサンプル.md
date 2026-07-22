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
