import Foundation
enum MPRoster {
    static let all: [MPHousePlayer] = [
        .init(id: "minik", english: "Mega Minik", hebrew: "מגה מיניק", profile: .init(speed: 6, reaction: 6, accuracy: 6, power: 6, agility: 6, characterId: "minik", forehandSkill: 6, backhandSkill: 6, serveSkill: 6)),
        .init(id: "flare", english: "Flare", hebrew: "Flare", profile: .init(speed: 9, reaction: 9, accuracy: 9, power: 9, agility: 9, characterId: "flare", forehandSkill: 9, backhandSkill: 9, serveSkill: 9)),
        .init(id: "kyra", english: "Kyra", hebrew: "ספיר", profile: .init(speed: 10, reaction: 10, accuracy: 10, power: 10, agility: 10, characterId: "kyra", forehandSkill: 10, backhandSkill: 10, serveSkill: 10)),
        .init(id: "gaya", english: "Gaya", hebrew: "גאיה", profile: .init(speed: 8, reaction: 8, accuracy: 8, power: 8, agility: 8, characterId: "gaya", forehandSkill: 8, backhandSkill: 8, serveSkill: 8)),
        .init(id: "mia", english: "Mia", hebrew: "מיה", profile: .init(speed: 7, reaction: 7, accuracy: 7, power: 7, agility: 7, characterId: "mia", forehandSkill: 7, backhandSkill: 7, serveSkill: 7)),
        .init(id: "amber", english: "Amber", hebrew: "ענבר", profile: .init(speed: 5, reaction: 5, accuracy: 6, power: 4, agility: 5, characterId: "amber", forehandSkill: 6, backhandSkill: 4, serveSkill: 7)),
        .init(id: "comet", english: "Comet", hebrew: "שביט", profile: .init(speed: 8, reaction: 5, accuracy: 4, power: 8, agility: 8, characterId: "comet", forehandSkill: 5, backhandSkill: 3, serveSkill: 5)),
        .init(id: "june", english: "June", hebrew: "סהר", profile: .init(speed: 6, reaction: 5, accuracy: 5, power: 5, agility: 6, characterId: "june", forehandSkill: 5, backhandSkill: 7, serveSkill: 6)),
        .init(id: "moshiko", english: "Bouncy Bob", hebrew: "מושיקו", profile: .init(speed: 3, reaction: 3, accuracy: 4, power: 9, agility: 3, characterId: "moshiko", forehandSkill: 4, backhandSkill: 2, serveSkill: 3)),
        .init(id: "miniko", english: "Mega Miniko", hebrew: "מגה מיניקו", profile: .init(speed: 6, reaction: 5, accuracy: 6, power: 6, agility: 7, characterId: "miniko", forehandSkill: 6, backhandSkill: 5, serveSkill: 6)),
        .init(id: "coach67", english: "Coach67", hebrew: "Coach67", profile: .init(speed: 5, reaction: 7, accuracy: 7, power: 5, agility: 4, characterId: "coach67", forehandSkill: 7, backhandSkill: 6, serveSkill: 7)),
    ]
    static func find(_ id: String) -> MPHousePlayer? { all.first { $0.id == id } }
}
