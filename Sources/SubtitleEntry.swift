//
//  SubtitleEntry.swift
//  SubtitleApp
//
//  Model for a subtitle line with timestamp for auto-dismissal.
//

import Foundation

struct SubtitleEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let createdAt: Date

    static func == (lhs: SubtitleEntry, rhs: SubtitleEntry) -> Bool {
        lhs.id == rhs.id
    }
}
