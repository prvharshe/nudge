//
//  Item.swift
//  nudge
//
//  Created by Pranav Harshe on 07/03/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
