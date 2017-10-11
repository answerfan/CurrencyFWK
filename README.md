# CurrencyFWK
macOS/iOS framework for easy currency conversion (yahoo api)

To get started, first of all, import `CurrencyFWK.framework` to your app.

```swift
// Swift
import CurrencyFWK
```

Then, before using it, implement an instance of converter

```swift
// Swift
let converter = CurrencyRetrievalKit.sharedInstance
```

The function, you're looking for is `convert(from sourceCurrency: String, to destinationCurrency: String, forced: Bool = false, completion: ((Double)->())? = nil)`

Function takes string values, like "USD", "EUR", "GBP" etc.; boolean value for force retrieval or not (I recommend "false") and in completion handler it returns conversion rate, meaning, for example, 1USD/1EUR.

Some func are written, using [Alamofire](https://github.com/Alamofire/Alamofire/), it's located in the "Frameworks" folder of CurrencyFWK.framework

It's my first framework, don't be too strict.
