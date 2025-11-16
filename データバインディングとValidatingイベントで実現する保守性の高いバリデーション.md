## はじめに

WinFormsアプリケーションでのバリデーション実装には様々な方法がありますが、本記事では**データバインディング**と**Validatingイベント**を組み合わせた、保守性と使いやすさを両立した実装方法を紹介します。

### 開発環境
- 開発対象: .NET Framework 4.8
- 開発言語: VB.NET

### この実装方法のメリット
- ✅ 入力途中でエラーが表示されない（UX向上）
- ✅ バリデーションルールをDTO側に集約できる
- ✅ データバインディングで自動的にDTOに値が反映される
- ✅ Web APIなど他の層でも同じDTOを使い回せる
- ✅ 保存時に一括バリデーションが可能

## 1. DTOクラスの実装

まず、`INotifyPropertyChanged`と`IDataErrorInfo`を実装したDTOクラスを作成します。

```vb
Imports System.ComponentModel
Imports System.ComponentModel.DataAnnotations

Public Class OrderDto
    Implements INotifyPropertyChanged
    Implements IDataErrorInfo
    
    Private _customerName As String
    Private _amount As Decimal?
    Private _phoneNumber As String
    Private _email As String
    Private errors As New Dictionary(Of String, String)
    
    ' 顧客名プロパティ
    <Required(ErrorMessage:="顧客名は必須です")>
    <StringLength(50, ErrorMessage:="顧客名は50文字以内で入力してください")>
    Public Property CustomerName As String
        Get
            Return _customerName
        End Get
        Set(value As String)
            If _customerName <> value Then
                _customerName = value
                OnPropertyChanged(NameOf(CustomerName))
                ValidateProperty(NameOf(CustomerName), value)
            End If
        End Set
    End Property
    
    ' 金額プロパティ
    <Required(ErrorMessage:="金額は必須です")>
    <Range(1, 1000000, ErrorMessage:="金額は1～1,000,000の範囲で入力してください")>
    Public Property Amount As Decimal?
        Get
            Return _amount
        End Get
        Set(value As Decimal?)
            If _amount <> value Then
                _amount = value
                OnPropertyChanged(NameOf(Amount))
                ValidateProperty(NameOf(Amount), value)
            End If
        End Set
    End Property
    
    ' 電話番号プロパティ
    <RegularExpression("^\d{3}-\d{4}-\d{4}$", ErrorMessage:="電話番号は000-0000-0000の形式で入力してください")>
    Public Property PhoneNumber As String
        Get
            Return _phoneNumber
        End Get
        Set(value As String)
            If _phoneNumber <> value Then
                _phoneNumber = value
                OnPropertyChanged(NameOf(PhoneNumber))
                ValidateProperty(NameOf(PhoneNumber), value)
            End If
        End Set
    End Property
    
    ' メールアドレスプロパティ
    <EmailAddress(ErrorMessage:="メールアドレスの形式が正しくありません")>
    Public Property Email As String
        Get
            Return _email
        End Get
        Set(value As String)
            If _email <> value Then
                _email = value
                OnPropertyChanged(NameOf(Email))
                ValidateProperty(NameOf(Email), value)
            End If
        End Set
    End Property
    
    ' IDataErrorInfo実装
    Public ReadOnly Property [Error] As String Implements IDataErrorInfo.Error
        Get
            Return String.Join(Environment.NewLine, errors.Values)
        End Get
    End Property
    
    Default Public ReadOnly Property Item(columnName As String) As String Implements IDataErrorInfo.Item
        Get
            If errors.ContainsKey(columnName) Then
                Return errors(columnName)
            End If
            Return String.Empty
        End Get
    End Property
    
    ' INotifyPropertyChanged実装
    Public Event PropertyChanged As PropertyChangedEventHandler Implements INotifyPropertyChanged.PropertyChanged
    
    Protected Sub OnPropertyChanged(propertyName As String)
        RaiseEvent PropertyChanged(Me, New PropertyChangedEventArgs(propertyName))
    End Sub
    
    ' プロパティごとのバリデーション
    Private Sub ValidateProperty(propertyName As String, value As Object)
        Dim context As New ValidationContext(Me) With {.MemberName = propertyName}
        Dim results As New List(Of ValidationResult)
        
        ' 既存のエラーをクリア
        errors.Remove(propertyName)
        
        ' バリデーション実行
        If Not Validator.TryValidateProperty(value, context, results) Then
            errors.Add(propertyName, results(0).ErrorMessage)
        End If
    End Sub
    
    ' 全体のバリデーション
    Public Function IsValid() As Boolean
        Dim context As New ValidationContext(Me)
        Dim results As New List(Of ValidationResult)
        
        ' 全プロパティをバリデーション
        Return Validator.TryValidateObject(Me, context, results, True)
    End Function
    
    ' エラーメッセージを全て取得
    Public Function GetAllErrors() As List(Of String)
        Return errors.Values.ToList()
    End Function
End Class
```

### データアノテーション属性の種類

| 属性 | 説明 | 使用例 |
|------|------|--------|
| `Required` | 必須入力 | `<Required(ErrorMessage:="必須です")>` |
| `StringLength` | 文字列長の制限 | `<StringLength(50, MinimumLength:=3)>` |
| `Range` | 数値範囲の制限 | `<Range(0, 100)>` |
| `RegularExpression` | 正規表現パターン | `<RegularExpression("^\d+$")>` |
| `EmailAddress` | メールアドレス形式 | `<EmailAddress()>` |
| `Phone` | 電話番号形式 | `<Phone()>` |
| `Url` | URL形式 | `<Url()>` |
| `Compare` | 他プロパティとの比較 | `<Compare("Password")>` |

## 2. フォームの実装

次に、データバインディングとValidatingイベントを設定したフォームを実装します。

```vb
Public Class OrderForm
    Private orderDto As New OrderDto()
    
    Private Sub OrderForm_Load(sender As Object, e As EventArgs) Handles MyBase.Load
        ' データバインディングの設定
        SetupDataBindings()
        
        ' Validatingイベントの設定
        AddHandler CustomerNameTextBox.Validating, AddressOf TextBox_Validating
        AddHandler AmountTextBox.Validating, AddressOf TextBox_Validating
        AddHandler PhoneNumberTextBox.Validating, AddressOf TextBox_Validating
        AddHandler EmailTextBox.Validating, AddressOf TextBox_Validating
    End Sub
    
    ' データバインディングの設定
    Private Sub SetupDataBindings()
        ' 顧客名
        CustomerNameTextBox.DataBindings.Add(
            "Text",
            orderDto,
            NameOf(orderDto.CustomerName),
            True,
            DataSourceUpdateMode.OnValidation
        )
        
        ' 金額
        AmountTextBox.DataBindings.Add(
            "Text",
            orderDto,
            NameOf(orderDto.Amount),
            True,
            DataSourceUpdateMode.OnValidation
        )
        
        ' 電話番号
        PhoneNumberTextBox.DataBindings.Add(
            "Text",
            orderDto,
            NameOf(orderDto.PhoneNumber),
            True,
            DataSourceUpdateMode.OnValidation
        )
        
        ' メールアドレス
        EmailTextBox.DataBindings.Add(
            "Text",
            orderDto,
            NameOf(orderDto.Email),
            True,
            DataSourceUpdateMode.OnValidation
        )
    End Sub
    
    ' Validatingイベント（フォーカスアウト時に実行）
    Private Sub TextBox_Validating(sender As Object, e As System.ComponentModel.CancelEventArgs)
        Dim textBox = CType(sender, TextBox)
        
        ' データバインディング情報を取得
        Dim binding = textBox.DataBindings("Text")
        If binding Is Nothing Then Return
        
        Dim propertyName = binding.BindingMemberInfo.BindingMember
        
        ' バインディングを更新してDTOに値を反映
        binding.WriteValue()
        
        ' DTOからエラーメッセージを取得
        Dim errorMessage = orderDto(propertyName)
        
        ' エラー表示の更新
        If Not String.IsNullOrEmpty(errorMessage) Then
            ErrorProvider1.SetError(textBox, errorMessage)
            textBox.BackColor = Color.LightPink
        Else
            ErrorProvider1.SetError(textBox, String.Empty)
            textBox.BackColor = Color.White
        End If
    End Sub
    
    ' 保存ボタンクリック
    Private Sub SaveButton_Click(sender As Object, e As EventArgs) Handles SaveButton.Click
        ' 全コントロールのバリデーションを実行
        If Not ValidateAllControls() Then
            MessageBox.Show(
                "入力内容に誤りがあります。" & Environment.NewLine & 
                String.Join(Environment.NewLine, orderDto.GetAllErrors()),
                "入力エラー",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning
            )
            Return
        End If
        
        ' DTOが有効かチェック
        If Not orderDto.IsValid() Then
            MessageBox.Show("入力内容に誤りがあります", "エラー", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If
        
        ' ビジネスロジック層へ渡す
        Try
            Dim service As New OrderService()
            Dim result = service.CreateOrder(orderDto)
            
            MessageBox.Show(
                "注文を保存しました。" & Environment.NewLine & 
                "注文番号: " & result.OrderId,
                "成功",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information
            )
            
            ' フォームをクリア
            ClearForm()
            
        Catch ex As Exception
            MessageBox.Show(
                "保存中にエラーが発生しました: " & ex.Message,
                "エラー",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            )
        End Try
    End Sub
    
    ' 全コントロールのバリデーション実行
    Private Function ValidateAllControls() As Boolean
        Dim isValid As Boolean = True
        
        ' 各TextBoxのValidatingを強制実行
        isValid = ValidateControl(CustomerNameTextBox) AndAlso isValid
        isValid = ValidateControl(AmountTextBox) AndAlso isValid
        isValid = ValidateControl(PhoneNumberTextBox) AndAlso isValid
        isValid = ValidateControl(EmailTextBox) AndAlso isValid
        
        Return isValid
    End Function
    
    ' 個別コントロールのバリデーション
    Private Function ValidateControl(textBox As TextBox) As Boolean
        Dim binding = textBox.DataBindings("Text")
        If binding Is Nothing Then Return True
        
        Dim propertyName = binding.BindingMemberInfo.BindingMember
        binding.WriteValue()
        
        Dim errorMessage = orderDto(propertyName)
        
        If Not String.IsNullOrEmpty(errorMessage) Then
            ErrorProvider1.SetError(textBox, errorMessage)
            textBox.BackColor = Color.LightPink
            Return False
        Else
            ErrorProvider1.SetError(textBox, String.Empty)
            textBox.BackColor = Color.White
            Return True
        End If
    End Function
    
    ' フォームをクリア
    Private Sub ClearForm()
        orderDto = New OrderDto()
        
        ' データバインディングを再設定
        For Each ctrl In Me.Controls.OfType(Of TextBox)()
            ctrl.DataBindings.Clear()
        Next
        
        SetupDataBindings()
        
        ' エラー表示をクリア
        ErrorProvider1.Clear()
        
        For Each ctrl In Me.Controls.OfType(Of TextBox)()
            ctrl.BackColor = Color.White
            ctrl.Clear()
        Next
    End Sub
End Class
```

## 3. ビジネスロジック層の実装

ビジネスロジック層はDTOを受け取って処理を行います。

```vb
Public Class OrderService
    Public Function CreateOrder(orderDto As OrderDto) As OrderResult
        ' ビジネスルールのバリデーション（DTOのバリデーションとは別）
        If orderDto.Amount.HasValue AndAlso orderDto.Amount.Value < 100 Then
            Throw New BusinessException("注文金額は100円以上である必要があります")
        End If
        
        ' データベース保存処理
        Dim orderId As Integer = SaveToDatabase(orderDto)
        
        ' メール送信などの処理
        SendConfirmationEmail(orderDto.Email, orderId)
        
        Return New OrderResult With {
            .OrderId = orderId,
            .Success = True
        }
    End Function
    
    Private Function SaveToDatabase(orderDto As OrderDto) As Integer
        ' DB保存処理（実装は省略）
        Return 12345 ' 仮の注文ID
    End Function
    
    Private Sub SendConfirmationEmail(email As String, orderId As Integer)
        ' メール送信処理（実装は省略）
    End Sub
End Class

Public Class OrderResult
    Public Property OrderId As Integer
    Public Property Success As Boolean
End Class

Public Class BusinessException
    Inherits Exception
    
    Public Sub New(message As String)
        MyBase.New(message)
    End Sub
End Class
```

## 4. カスタムバリデーション属性の作成

標準の属性では対応できない複雑なバリデーションは、カスタム属性を作成します。

```vb
Imports System.ComponentModel.DataAnnotations

' 日本の郵便番号バリデーション
Public Class JapanesePostalCodeAttribute
    Inherits ValidationAttribute
    
    Protected Overrides Function IsValid(value As Object, validationContext As ValidationContext) As ValidationResult
        If value Is Nothing OrElse String.IsNullOrWhiteSpace(value.ToString()) Then
            Return ValidationResult.Success
        End If
        
        Dim postalCode = value.ToString()
        
        ' 000-0000 形式をチェック
        If System.Text.RegularExpressions.Regex.IsMatch(postalCode, "^\d{3}-\d{4}$") Then
            Return ValidationResult.Success
        End If
        
        Return New ValidationResult("郵便番号は000-0000の形式で入力してください")
    End Function
End Class

' 日付範囲バリデーション
Public Class DateRangeAttribute
    Inherits ValidationAttribute
    
    Public Property MinimumDaysFromNow As Integer = 0
    Public Property MaximumDaysFromNow As Integer = 365
    
    Protected Overrides Function IsValid(value As Object, validationContext As ValidationContext) As ValidationResult
        If value Is Nothing Then
            Return ValidationResult.Success
        End If
        
        Dim targetDate As Date
        If Not Date.TryParse(value.ToString(), targetDate) Then
            Return New ValidationResult("有効な日付を入力してください")
        End If
        
        Dim minDate = Date.Today.AddDays(MinimumDaysFromNow)
        Dim maxDate = Date.Today.AddDays(MaximumDaysFromNow)
        
        If targetDate < minDate OrElse targetDate > maxDate Then
            Return New ValidationResult($"日付は{minDate:yyyy/MM/dd}～{maxDate:yyyy/MM/dd}の範囲で入力してください")
        End If
        
        Return ValidationResult.Success
    End Function
End Class

' 使用例
Public Class DeliveryDto
    <JapanesePostalCode>
    Public Property PostalCode As String
    
    <DateRange(MinimumDaysFromNow:=1, MaximumDaysFromNow:=30)>
    Public Property DeliveryDate As Date?
End Class
```

## 5. 複数フィールド間のバリデーション

複数のプロパティにまたがるバリデーションは、クラスレベルの属性で実装します。

```vb
Imports System.ComponentModel.DataAnnotations

' クラスレベルのバリデーション属性
Public Class DateRangeValidationAttribute
    Inherits ValidationAttribute
    
    Private ReadOnly _startDateProperty As String
    Private ReadOnly _endDateProperty As String
    
    Public Sub New(startDateProperty As String, endDateProperty As String)
        _startDateProperty = startDateProperty
        _endDateProperty = endDateProperty
    End Sub
    
    Protected Overrides Function IsValid(value As Object, validationContext As ValidationContext) As ValidationResult
        Dim startDateProp = validationContext.ObjectType.GetProperty(_startDateProperty)
        Dim endDateProp = validationContext.ObjectType.GetProperty(_endDateProperty)
        
        If startDateProp Is Nothing OrElse endDateProp Is Nothing Then
            Return New ValidationResult("プロパティが見つかりません")
        End If
        
        Dim startDate = CType(startDateProp.GetValue(validationContext.ObjectInstance), Date?)
        Dim endDate = CType(endDateProp.GetValue(validationContext.ObjectInstance), Date?)
        
        If startDate.HasValue AndAlso endDate.HasValue AndAlso startDate.Value > endDate.Value Then
            Return New ValidationResult("終了日は開始日より後の日付を指定してください")
        End If
        
        Return ValidationResult.Success
    End Function
End Class

' 使用例
<DateRangeValidation("StartDate", "EndDate")>
Public Class PeriodDto
    <Required>
    Public Property StartDate As Date?
    
    <Required>
    Public Property EndDate As Date?
End Class
```

## 6. 実行時の動作

### 入力中の動作
1. ユーザーがTextBoxに値を入力
2. フォーカスが外れる（別のコントロールに移動）
3. Validatingイベントが発火
4. データバインディングによりDTOに値が反映
5. DTOのSetterで自動的にバリデーション実行
6. エラーがあればErrorProviderで表示

### 保存時の動作
1. 保存ボタンクリック
2. `ValidateAllControls()`で全コントロールを検証
3. `orderDto.IsValid()`でDTO全体を検証
4. 問題なければビジネスロジック層へ
5. データベース保存

## 7. メリットとデメリット

### メリット
- **UXの向上**: 入力途中でエラーが出ないため、ユーザーストレスが少ない
- **保守性**: バリデーションルールがDTO側に集約され、修正が容易
- **再利用性**: 同じDTOをWeb API層などでも利用可能
- **テスタビリティ**: DTOとビジネスロジックが分離されており、単体テストが容易
- **一貫性**: データアノテーションにより、バリデーションルールが宣言的で分かりやすい

### デメリット
- **初期実装コスト**: 最初の実装に若干の手間がかかる
- **学習コスト**: データバインディングやインターフェース実装の理解が必要
- **リアルタイムフィードバック不可**: Changedイベントではなく、Validatingイベントのため、入力中のエラー表示はできない

## 8. 応用: 動的にバリデーションルールを変更

状況に応じてバリデーションルールを変更したい場合の実装例です。

```vb
Public Class DynamicOrderDto
    Inherits OrderDto
    
    Public Property OrderType As String ' "個人" or "法人"
    
    ' 個人の場合のみ必須
    Public Overrides Property CustomerName As String
        Get
            Return MyBase.CustomerName
        End Get
        Set(value As String)
            MyBase.CustomerName = value
            
            ' 個人の場合のみバリデーション
            If OrderType = "個人" Then
                If String.IsNullOrWhiteSpace(value) Then
                    errors(NameOf(CustomerName)) = "個人注文の場合、顧客名は必須です"
                Else
                    errors.Remove(NameOf(CustomerName))
                End If
            Else
                errors.Remove(NameOf(CustomerName))
            End If
        End Set
    End Property
End Class
```

## おわりに

データバインディングとValidatingイベントを組み合わせることで、保守性が高く、ユーザーフレンドリーなバリデーション機能を実装できます。

特に以下のようなケースで効果を発揮します：
- 入力項目が多いフォーム
- バリデーションルールが頻繁に変更される
- DTOを複数の層（UI層、API層など）で共有したい
- 単体テストを重視したい

ぜひプロジェクトで活用してみてください！
