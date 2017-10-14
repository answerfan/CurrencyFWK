//
//  CurrencuRetrievalKit.swift
//  CurrencyFWK
//
//  Created by a.boriskin on 09/10/2017.
//  Copyright © 2017 a.boriskin. All rights reserved.
//

import Cocoa
import Alamofire

internal var CRKInstance : CurrencyRetrievalKit!

@objc protocol CurrencyRetrievalKitDelegate : class {
    func didFinishParsingSingleUnit(_ fromUnit: String, toUnit:String, rate: Double)
    func didFailToParse(_ fromUnit: String, toUnit:String)
    
    var rates : [Rate] { get set }
}

@objc public class CurrencyRetrievalKit: NSObject {

    @objc public static let sharedInstance = CurrencyRetrievalKit()
    
    internal weak var delegate: CurrencyRetrievalKitDelegate?
    
    private var rates : [Rate] = []
    private var sourceUnit, telicUnit : String!
    private var operationQueue = DispatchQueue.init(label: "yahoo.queue", qos: .userInitiated)
    private var timer : Timer!
    private var scheduledClosure : (()->())!
    private var flippedPairs: [String : [String]] = [String:[String]]()
    
    public var lastFetchDate : Date! = UserDefaults.standard.value(forKey: "lastfetch") as? Date ?? nil
    
    public lazy var currencyUnits : [String] = {
        return self.currencies.keys.sorted()
    }()
    
    
    @objc public let currencies = [
        "AUD" : "Австралийский доллар",
        "AZN" : "Азербайджанский манат",
        "BGN" : "Болгарский лев",
        "BRL" : "Бразильский реал",
        "BYN" : "Белорусский рубль",
        "CAD" : "Канадский доллар",
        "CHF" : "Швейцарский франк",
        "CNY" : "Китайский юань",
        "CZK" : "Чешская крона",
        "DKK" : "Датская крона",
        "EUR" : "Евро",
        "GBP" : "Фунт стерлингов",
        "HKD" : "Гонконгский доллар",
        "HUF" : "Венгерский форинт",
        "INR" : "Индийская рупия",
        "JPY" : "Японская иена",
        "KGS" : "Киргизский сом",
        "KRW" : "Южнокорейская вона",
        "KZT" : "Казахстанский тенге",
        "MDL" : "Молдавский лей",
        "NOK" : "Норвежская крона",
        "PLN" : "Польский злотый",
        "RON" : "Румынский лей",
        "RUB" : "Российский рубль",
        "SEK" : "Шведская крона",
        "SGD" : "Сингапурский доллар",
        "TJS" : "Таджикский рубль",
        "TMT" : "Туркменский манат",
        "TRY" : "Турецкая лира",
        "UAH" : "Украинская гривна",
        "USD" : "Доллар США",
        "UZS" : "Узбекский сум",
        "XDR" : "СДР",
        "ZAR" : "Южноафриканский рэнд"
    ]
    
    @objc public let cryptoCurrencies = [
        // "USD" : "Доллар США",
        "BTC" : "Bitcoin",
        "ETH" : "Ethereum",
        "XRP" :    "Ripple",
        "XEM" : "NEM",
        "ETC" : "Ethereum Classic",
        "LTC" : "Litecoin",
        "STRAT" : "Stratis",
        "DASH" : "Dash",
        "XMR" : "Monero",
        "WAVES"  : "Waves"
    ]
    
    @objc public let cryptoCurrency = [
        "USD" : "Доллар США"
    ]
    
    
    //        ["MXN", "LTL", "ILS", "MYR", "THB", "SEK", "AUD", "GBP", "HRK", "INR", "LVL", "HKD", "HUF", "ISK", "PHP", "PLN", "NZD", "IDR", "SGD","CAD", "DKK", "EUR", "CNY", "JPY", "ZAR", "CHF", "BGN", "CZK", "TRY", "RUB", "BRL", "NOK", "RON", "KRW", "USD"].sorted()
    
    @objc public func units(except: String? = nil) -> [String] {
        if except == nil { return currencyUnits }
        return currencyUnits.filter { $0 != except }
    }
    
    @objc public func setflippedPairs(_ pairs: [String: [String]]) {
        flippedPairs = pairs
    }
    
    // MARK: - Init
    private override init() {
        super.init()

        if let data = UserDefaults.standard.data(forKey: "rates"),
            let savedRates = NSKeyedUnarchiver.unarchiveObject(with: data) as? [Rate] {
            objc_sync_enter(self.rates)
            let ratesFilter = savedRates.filter { $0.name != ""}
            self.rates = ratesFilter
            objc_sync_exit(self.rates)
            print("Last fetch date  \(lastFetchDate!)")
        }
        
        if Reachability.isConnectedToNetwork() {
            fetchRates()
            
        }
    }
    
    deinit {
        timer.invalidate()
        scheduledClosure = nil
    }
    
    @objc public func dictionary(for currency: String) -> [String: Double] {
        var dict = [String : Double]()
        
        rates.filter({ $0.from == currency}).forEach { dict[$0.from] = $0.rate }
        if dict.count > 0 { return dict }
        
        let sema = DispatchSemaphore.init(value: 0)
        fetchRates(for: currency) { [unowned self] _ in
            self.rates.filter({ $0.from == currency}).forEach {
                dict[$0.to] = $0.rate
            }
            sema.signal()
        }
        sema.wait()
        
        return dict
    }
    
    
    @objc public func scheduleUpdates(interval: Int, closure: (()->())? = nil) {
        scheduledClosure = closure
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(interval), target: self, selector: #selector(self.fullFetch), userInfo: nil, repeats: true)
    }
    
    @objc public func terminateUpdates() {
        timer?.invalidate()
        scheduledClosure = nil
    }
    
    
    
    @objc private func fullFetch(){
        if Reachability.isConnectedToNetwork() {
            self.fetchRates(forced: true)
        }
        scheduledClosure?()
    }
    
    
    
    // MARK: - Main function
    @objc public func convert(from sourceCurrency: String, to destinationCurrency: String, forced: Bool = false, completion: ((Double)->())? = nil) {
        
        // Если from = to, возвращаем единицу (т.к. конвертер её не вернет)
        if (sourceCurrency == destinationCurrency) {
            delegate?.didFinishParsingSingleUnit(sourceCurrency, toUnit: destinationCurrency, rate: 1)
            completion?(1)
            return
        }
        
        // Если в массиве уже есть данные об этой конверсии, просто сообщаем об этом делегату.
        self.rates = self.rates.filter({ $0.name != "" })
        if !forced, let soughtItem = self.rates.filter( {$0.from == sourceCurrency && $0.to == destinationCurrency}).first {
            // Объект найден
            delegate?.didFinishParsingSingleUnit(sourceUnit, toUnit: soughtItem.to, rate: soughtItem.rate)
            completion?(soughtItem.rate)
            return
        }
        if !forced, let soughtItem = self.rates.filter( {$0.from == destinationCurrency && $0.to == sourceCurrency}).first {
            // Объект найден
            delegate?.didFinishParsingSingleUnit(sourceUnit, toUnit: soughtItem.to, rate: soughtItem.rate)
            completion?(1 / soughtItem.rate)
            return
        }
        
        if Reachability.isConnectedToNetwork() {
            fetchRates(for: sourceCurrency, to: destinationCurrency, forced: forced) { rate in completion?(rate)}
        }
        else {
            if let existing = self.rates.filter( {$0.from == sourceCurrency && $0.to == destinationCurrency}).last {
                completion?(existing.rate)
            } else {
                completion?(-1)
            }
        }
    }
    
    
    private func fetchRates(for source: String! = nil, to resulting: String! = nil, forced : Bool? = false, completion: ((Double)->())? = nil) {
        if (source == nil && resulting == nil) {
            return
        }
        operationQueue.async {
            for sourceUnit in (source == nil ? self.currencyUnits : [source]) {
                self.operationQueue.suspend()
                
                // Query term is a list of conversion pairs: "USDEUR", "USDRUB", ...
                let term = "\"" + source + resulting + "\""
                
                
                
                Alamofire.request("https://query.yahooapis.com/v1/public/yql",
                                  parameters: ["q" : "select * from yahoo.finance.xchange where pair in (\(term))",
                                    "env" : "store://datatables.org/alltableswithkeys",
                                    "format" : "json"])
                    
                    .responseJSON(queue: DispatchQueue.global(qos: .userInitiated), completionHandler: {
                        [unowned self] response in switch response.result {
                            
                        case .failure(let error):
                            // self.operationQueue.resume()
                            print("Error while fetching rates: \(String(describing: error))")
                            return
                            
                        case .success(let data):
                            let json = JSON(data)
                            guard let count = json["query"]["count"].int, count != 0 else {
                                // self.operationQueue.resume()
                                completion?(0)
                                print("Error while fetching rates: No results)")
                                return
                            }
                            let jsonRates = json["query"]["results"]["rate"]
                            var results = [JSON]()

                            results.append(jsonRates)
                            
                            objc_sync_enter(self)
                            
                            
                            let excluded = self.rates
                            self.rates = excluded
                            let rate = Double((results.first?["Rate"].string!)!)!
                            self.rates.append(Rate(id: "0",
                                                   name: source + "/" + resulting,
                                                   rate: rate,
                                                   date: "",
                                                   time: ""))
                            let encodedData = NSKeyedArchiver.archivedData(withRootObject: self.rates)
                            self.lastFetchDate = Date()
                            UserDefaults.standard.set(encodedData, forKey: "rates")
                            UserDefaults.standard.set(self.lastFetchDate, forKey: "lastfetch")
                            UserDefaults.standard.synchronize()
                            if (forced)! {
                                completion?(rate)
                            }
                            
                            objc_sync_exit(self)

                            self.operationQueue.resume()
                        }
                    })
            }
        }
    }
    
    private func postToken(){
    }
    
    private func queryTerm (for unit: String? = nil) -> String {
        var queryTerm = ""
        
        let soughtUnits = unit != nil ? [unit!] : currencyUnits
        
        for sourceUnit in soughtUnits {
            for u in currencyUnits.filter({ $0 != unit }) {
                queryTerm += "\"\(sourceUnit)\(u)\", "
            }
        }
        
        return String(queryTerm.characters.dropLast(2)) // drop last: ,%20
    }
    
}

internal class CRKInterFace<T> : CRKitFunctions where T:Rate{
//    func convert(fromCurr: String, toCurr: String, completion: @escaping () -> ()) -> Double {
//        <#code#>
//    }
    
    
    
    private var entity : T
    
    init(for entity: T){
        self.entity = entity
    }
    
    
    
//    func save() {
//        sharedInstance?.iCloudSave(entity)
//    }
//
//    func saveAndWait() {
//        _ = sharedInstance?.saveRecordSync(entity: entity, submitBlock: nil, completionHandler: sharedInstance?.delegate.zenEntityDidSaveToCloud)
//    }
//
//    func delete() {
//        sharedInstance?.iCloudDelete(entity)
//    }
//
//    func saveKeys(_ keys: [String]) {
//        sharedInstance?.iCloudSaveKeys(entity, keys: keys)
//    }
//
//    func saveKeysAndWait(_ keys: [String]) {
//        sharedInstance?.iCloudSaveKeysAndWait(entity, keys: keys)
//    }
//
//    func update (fromRemote record: CKRecord, fetchReferences fetch: Bool = false) {
//        sharedInstance?.updateEntity(self as! ZKEntity, fromRemote: record, fetchReferences: fetch)
//    }
}
