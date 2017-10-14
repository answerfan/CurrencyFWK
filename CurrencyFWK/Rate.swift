//
//  Rate.swift
//  CurrencyFWK
//
//  Created by a.boriskin on 03/10/2017.
//  Copyright © 2017 a.boriskin. All rights reserved.
//

import Cocoa

class Rate: NSObject, NSCoding {

    var id: String!
    var name: String!
    var rate: Double!
    var date: String!
    var time: String!
    
    var from : String { return name.substring(to: 3) }
    var to: String { return name.substring(from: 4) }
    
    convenience init(id: String!, name: String!, rate: Double!, date: String!, time: String!) {
        self.init()
        
        self.id = id
        self.name = name
        self.rate = rate
        self.date = date
        self.time = time
        
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(id, forKey: "id")
        aCoder.encode(name, forKey: "name")
        aCoder.encode(rate, forKey: "rate")
        aCoder.encode(date, forKey: "date")
        aCoder.encode(time, forKey: "time")
    }
    
    required convenience init?(coder aDecoder: NSCoder) {
        self.init()
        
        id = aDecoder.decodeObject(forKey: "id") as? String ?? ""
        name = aDecoder.decodeObject(forKey: "name") as? String ?? ""
        rate = aDecoder.decodeObject(forKey: "rate") as? Double ?? 0
        date = aDecoder.decodeObject(forKey: "date") as? String ?? ""
        time = aDecoder.decodeObject(forKey: "time") as? String ?? ""
    }
    
}

extension String {
    func index(from: Int) -> Index {
        return self.index(startIndex, offsetBy: from)
    }
    
    func substring(from: Int) -> String {
        //   let fromIndex = index(from: from)
        var pos = 3
        if let idx = self.characters.index(of: "/") {
            pos = self.characters.distance(from: self.startIndex, to: idx)
        }
        let fromIndex = index(from : pos + 1)
        return substring(from: fromIndex)
    }
    
    func substring(to: Int) -> String {
        var pos = 3
        if let idx = self.characters.index(of: "/") {
            pos = self.characters.distance(from: self.startIndex, to: idx)
        }
        let toIndex = index(from: pos)
        // let toIndex = index(from: to)
        return substring(to: toIndex)
    }
    
    
    func substring(with r: Range<Int>) -> String {
        let startIndex = index(from: r.lowerBound)
        let endIndex = index(from: r.upperBound)
        return substring(with: startIndex..<endIndex)
    }
}
