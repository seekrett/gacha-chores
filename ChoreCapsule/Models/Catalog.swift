import SwiftUI

enum Rarity: String, Codable, CaseIterable, Comparable {
    case common, rare, epic, secret

    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.order < rhs.order }

    var order: Int {
        switch self {
        case .common: 0
        case .rare: 1
        case .epic: 2
        case .secret: 3
        }
    }

    var label: String {
        switch self {
        case .common: "Common"
        case .rare: "Rare"
        case .epic: "Epic"
        case .secret: "Secret"
        }
    }

    /// Drop rates for a capsule pull.
    var rate: Double {
        switch self {
        case .common: 0.62
        case .rare: 0.27
        case .epic: 0.09
        case .secret: 0.02
        }
    }

    var color: Color {
        switch self {
        case .common: Color(hex: 0x6FCFAE)
        case .rare: Color(hex: 0x5AA9FF)
        case .epic: Color(hex: 0xB070FF)
        case .secret: Color(hex: 0xFFB800)
        }
    }

    var stars: Int { order + 1 }

    /// Glitter you get for a duplicate.
    var glitterValue: Int {
        switch self {
        case .common: 5
        case .rare: 15
        case .epic: 40
        case .secret: 120
        }
    }

    /// Price to buy outright in the shop. Secrets can only be pulled.
    var shopPrice: Int? {
        switch self {
        case .common: 300
        case .rare: 750
        case .epic: 2000
        case .secret: nil
        }
    }
}

enum EarStyle: Hashable { case bunny, cat, bear, floppy, antenna, horns, sprout, none }
enum EyeStyle: Hashable { case dot, sparkle, sleepy, happy, wink, star }
enum MouthStyle: Hashable { case smile, cat, open, fang, tiny }
enum BodyPattern: Hashable { case none, spots, stripes, hearts }

struct FigureLook: Hashable {
    var body: Color
    var belly: Color = .white.opacity(0.55)
    var accent: Color = Palette.berry
    var ears: EarStyle = .none
    var eyes: EyeStyle = .dot
    var mouth: MouthStyle = .smile
    var pattern: BodyPattern = .none
    var hat: String? = nil
    var held: String? = nil
    var holo = false
}

struct FigureDef: Identifiable, Hashable {
    let id: String
    let name: String
    let seriesID: String
    let rarity: Rarity
    let flavor: String
    let look: FigureLook

    var series: Series { Catalog.series(seriesID) }
}

struct Series: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let symbol: String
    let colors: [Color]
    let completionReward: Int
}

enum Catalog {
    static let series: [Series] = [
        Series(id: "dust", name: "Dust Bunny Club",
               tagline: "Tiny tidy-up champions who live under your couch.",
               symbol: "sparkles", colors: [Color(hex: 0xFF9EC4), Color(hex: 0xC59BFF)], completionReward: 500),
        Series(id: "night", name: "Cozy Night Critters",
               tagline: "Sleepy friends for people who actually made their bed.",
               symbol: "moon.stars.fill", colors: [Color(hex: 0x6C7BFF), Color(hex: 0x2E2A6B)], completionReward: 500),
        Series(id: "sprout", name: "Sprout Squad",
               tagline: "Little plant pals that grow when you do.",
               symbol: "leaf.fill", colors: [Color(hex: 0x8EE07A), Color(hex: 0x2FA37A)], completionReward: 500),
        Series(id: "sweet", name: "Sweet Treat Pals",
               tagline: "Dessert buddies. Zero calories, all serotonin.",
               symbol: "birthday.cake.fill", colors: [Color(hex: 0xFFC27A), Color(hex: 0xFF7FA8)], completionReward: 500),
    ]

    static let figures: [FigureDef] = dust + night + sprout + sweet

    static let byID: [String: FigureDef] = Dictionary(uniqueKeysWithValues: figures.map { ($0.id, $0) })

    static func series(_ id: String) -> Series {
        series.first { $0.id == id } ?? series[0]
    }

    static func figures(in seriesID: String) -> [FigureDef] {
        figures.filter { $0.seriesID == seriesID }
    }

    static func figures(in seriesID: String, rarity: Rarity) -> [FigureDef] {
        figures.filter { $0.seriesID == seriesID && $0.rarity == rarity }
    }

    // MARK: Dust Bunny Club

    private static let dust: [FigureDef] = [
        FigureDef(id: "dust_fluff", name: "Fluff", seriesID: "dust", rarity: .common,
                  flavor: "Was once a dust bunny. Got adopted. Now insists on a clean floor.",
                  look: FigureLook(body: Color(hex: 0xFFD3E4), accent: Color(hex: 0xFF7FAE), ears: .bunny, eyes: .dot, mouth: .cat)),
        FigureDef(id: "dust_moptop", name: "Mop Top", seriesID: "dust", rarity: .common,
                  flavor: "Has never had a good hair day. Has never had a dirty floor either.",
                  look: FigureLook(body: Color(hex: 0xFFF1D6), accent: Color(hex: 0x7EC8FF), ears: .floppy, eyes: .sleepy, mouth: .smile, held: "bubbles.and.sparkles.fill")),
        FigureDef(id: "dust_bandit", name: "Laundry Bandit", seriesID: "dust", rarity: .common,
                  flavor: "Steals one sock per load. Returns it if you fold everything.",
                  look: FigureLook(body: Color(hex: 0xC9C3E8), accent: Color(hex: 0x6C5BD4), ears: .bunny, eyes: .wink, mouth: .fang, held: "tshirt.fill")),
        FigureDef(id: "dust_crumb", name: "Crumb", seriesID: "dust", rarity: .common,
                  flavor: "Found under the toaster. Smells faintly of bagel.",
                  look: FigureLook(body: Color(hex: 0xE8C49A), accent: Color(hex: 0xB07A45), ears: .bear, eyes: .dot, mouth: .open, pattern: .spots)),
        FigureDef(id: "dust_suds", name: "Sir Suds", seriesID: "dust", rarity: .rare,
                  flavor: "Knighted for bravery in the Battle of the Burnt Pan.",
                  look: FigureLook(body: Color(hex: 0xA9DBFF), accent: Color(hex: 0x3E8EE8), ears: .bunny, eyes: .sparkle, mouth: .smile, held: "drop.fill")),
        FigureDef(id: "dust_sweep", name: "Sparkle Sweep", seriesID: "dust", rarity: .rare,
                  flavor: "Leaves a trail of glitter. Ironically, has to clean it up.",
                  look: FigureLook(body: Color(hex: 0xB5F0DA), accent: Color(hex: 0x2FB58A), ears: .cat, eyes: .star, mouth: .cat, held: "wand.and.stars")),
        FigureDef(id: "dust_duchess", name: "Duchess Dustpan", seriesID: "dust", rarity: .epic,
                  flavor: "Rules the hallway closet with a velvet glove and a firm broom.",
                  look: FigureLook(body: Color(hex: 0xD9C2FF), accent: Color(hex: 0xFFB800), ears: .bunny, eyes: .sparkle, mouth: .tiny, pattern: .hearts, hat: "crown.fill")),
        FigureDef(id: "dust_golden", name: "Golden Vac", seriesID: "dust", rarity: .secret,
                  flavor: "Legend says it only appears to people who vacuum under the bed.",
                  look: FigureLook(body: Color(hex: 0xFFD65A), belly: Color(hex: 0xFFF4C2), accent: Color(hex: 0xFF9D00), ears: .bunny, eyes: .star, mouth: .open, hat: "crown.fill", held: "star.fill", holo: true)),
    ]

    // MARK: Cozy Night Critters

    private static let night: [FigureDef] = [
        FigureDef(id: "night_pillow", name: "Pillow Puff", seriesID: "night", rarity: .common,
                  flavor: "Fluffs itself every morning. Judges you if you don't.",
                  look: FigureLook(body: Color(hex: 0xE4ECFF), accent: Color(hex: 0x8A9CFF), ears: .bear, eyes: .sleepy, mouth: .cat)),
        FigureDef(id: "night_owlet", name: "Owlet", seriesID: "night", rarity: .common,
                  flavor: "Stays up late so you don't have to. Go to bed.",
                  look: FigureLook(body: Color(hex: 0xC49A7A), belly: Color(hex: 0xF5E1CC), accent: Color(hex: 0x7A5238), ears: .horns, eyes: .sparkle, mouth: .tiny)),
        FigureDef(id: "night_burrito", name: "Blanket Burrito", seriesID: "night", rarity: .common,
                  flavor: "Fully wrapped. Will not be unwrapped until the dishes are done.",
                  look: FigureLook(body: Color(hex: 0xFFCBA8), accent: Color(hex: 0xFF8A5C), ears: .none, eyes: .happy, mouth: .smile, pattern: .stripes)),
        FigureDef(id: "night_chamomile", name: "Chamomile", seriesID: "night", rarity: .common,
                  flavor: "Brews one cup of tea per tidy room. Very hydrated.",
                  look: FigureLook(body: Color(hex: 0xCDE3C3), accent: Color(hex: 0x6FA35A), ears: .cat, eyes: .dot, mouth: .smile, held: "cup.and.saucer.fill")),
        FigureDef(id: "night_moonbeam", name: "Moonbeam", seriesID: "night", rarity: .rare,
                  flavor: "Glows softly when you finish your to-do list before 9 pm.",
                  look: FigureLook(body: Color(hex: 0xFFF3B0), accent: Color(hex: 0xF0B400), ears: .antenna, eyes: .sparkle, mouth: .cat, held: "moon.fill")),
        FigureDef(id: "night_dream", name: "Dream Catcher", seriesID: "night", rarity: .rare,
                  flavor: "Catches bad dreams and unread emails. Mostly emails.",
                  look: FigureLook(body: Color(hex: 0xD8C8FF), accent: Color(hex: 0x8C6CFF), ears: .floppy, eyes: .wink, mouth: .smile, held: "cloud.fill")),
        FigureDef(id: "night_stargazer", name: "Stargazer", seriesID: "night", rarity: .epic,
                  flavor: "Has named every star after a chore you finished.",
                  look: FigureLook(body: Color(hex: 0x6F78E8), belly: Color(hex: 0xC9D0FF), accent: Color(hex: 0xFFE27A), ears: .cat, eyes: .star, mouth: .open, pattern: .spots, hat: "moon.stars.fill")),
        FigureDef(id: "night_aurora", name: "Aurora", seriesID: "night", rarity: .secret,
                  flavor: "Seen once every hundred nights. Shimmers like a well-kept home.",
                  look: FigureLook(body: Color(hex: 0xBFE9FF), accent: Color(hex: 0x9B7BFF), ears: .horns, eyes: .star, mouth: .cat, held: "sparkles", holo: true)),
    ]

    // MARK: Sprout Squad

    private static let sprout: [FigureDef] = [
        FigureDef(id: "sprout_seedling", name: "Seedling", seriesID: "sprout", rarity: .common,
                  flavor: "Everyone starts small. Seedling started very small.",
                  look: FigureLook(body: Color(hex: 0xC8F2A8), accent: Color(hex: 0x4FB54A), ears: .sprout, eyes: .dot, mouth: .smile)),
        FigureDef(id: "sprout_prickles", name: "Prickles", seriesID: "sprout", rarity: .common,
                  flavor: "Prickly about clutter. Soft about everything else.",
                  look: FigureLook(body: Color(hex: 0x8ED39A), accent: Color(hex: 0x2E8A4A), ears: .none, eyes: .wink, mouth: .fang, pattern: .spots)),
        FigureDef(id: "sprout_shroomie", name: "Shroomie", seriesID: "sprout", rarity: .common,
                  flavor: "Grows in damp corners. Please wipe down the shower.",
                  look: FigureLook(body: Color(hex: 0xFF8E8E), belly: Color(hex: 0xFFF1E6), accent: Color(hex: 0xFFFFFF), ears: .bear, eyes: .sparkle, mouth: .tiny, pattern: .spots)),
        FigureDef(id: "sprout_beanie", name: "Beanie", seriesID: "sprout", rarity: .common,
                  flavor: "Full of beans. Literally. Do not ask.",
                  look: FigureLook(body: Color(hex: 0xDDF27A), accent: Color(hex: 0x8DB51C), ears: .antenna, eyes: .dot, mouth: .open)),
        FigureDef(id: "sprout_blossom", name: "Blossom", seriesID: "sprout", rarity: .rare,
                  flavor: "Blooms a little every time you water your plants (and yourself).",
                  look: FigureLook(body: Color(hex: 0xFFC6DD), accent: Color(hex: 0xF0559A), ears: .sprout, eyes: .sparkle, mouth: .cat, held: "camera.macro")),
        FigureDef(id: "sprout_sensei", name: "Bonsai Sensei", seriesID: "sprout", rarity: .rare,
                  flavor: "\"A tidy desk is a tidy mind.\" Has said this 4,000 times.",
                  look: FigureLook(body: Color(hex: 0xB9C77A), accent: Color(hex: 0x6B7A2A), ears: .bear, eyes: .sleepy, mouth: .smile, held: "tree.fill")),
        FigureDef(id: "sprout_sunny", name: "Sunny", seriesID: "sprout", rarity: .epic,
                  flavor: "Always faces the brightest part of the room: wherever you just cleaned.",
                  look: FigureLook(body: Color(hex: 0xFFE066), belly: Color(hex: 0xFFF6CC), accent: Color(hex: 0xFF9F1C), ears: .sprout, eyes: .star, mouth: .open, hat: "sun.max.fill")),
        FigureDef(id: "sprout_grove", name: "Elder Grove", seriesID: "sprout", rarity: .secret,
                  flavor: "The oldest sprout. Has seen a thousand to-do lists finished.",
                  look: FigureLook(body: Color(hex: 0x9FF0C8), accent: Color(hex: 0xFFC94D), ears: .horns, eyes: .sparkle, mouth: .smile, hat: "leaf.fill", held: "sparkles", holo: true)),
    ]

    // MARK: Sweet Treat Pals

    private static let sweet: [FigureDef] = [
        FigureDef(id: "sweet_mochi", name: "Mochi", seriesID: "sweet", rarity: .common,
                  flavor: "Squishy, round, and extremely proud of you.",
                  look: FigureLook(body: Color(hex: 0xFFF0F4), accent: Color(hex: 0xFF9EC4), ears: .none, eyes: .happy, mouth: .cat)),
        FigureDef(id: "sweet_pudding", name: "Pudding", seriesID: "sweet", rarity: .common,
                  flavor: "Wobbles when happy. Wobbles a lot after chore day.",
                  look: FigureLook(body: Color(hex: 0xFFE39A), accent: Color(hex: 0xB0702A), ears: .bear, eyes: .dot, mouth: .smile, pattern: .stripes)),
        FigureDef(id: "sweet_sprinkles", name: "Sprinkles", seriesID: "sweet", rarity: .common,
                  flavor: "Leaves sprinkles everywhere. Cleans them up. Character growth.",
                  look: FigureLook(body: Color(hex: 0xFFB7D5), accent: Color(hex: 0x7A6CFF), ears: .cat, eyes: .wink, mouth: .open, pattern: .spots)),
        FigureDef(id: "sweet_boba", name: "Boba", seriesID: "sweet", rarity: .common,
                  flavor: "Brown sugar, 50% sweet, 100% motivated.",
                  look: FigureLook(body: Color(hex: 0xE3C2A0), accent: Color(hex: 0x5A3A2A), ears: .bunny, eyes: .dot, mouth: .open, held: "mug.fill")),
        FigureDef(id: "sweet_macaron", name: "Macaron", seriesID: "sweet", rarity: .rare,
                  flavor: "Delicate. Fancy. Refuses to sit on a sticky counter.",
                  look: FigureLook(body: Color(hex: 0xB8F0E0), accent: Color(hex: 0xFF8FB8), ears: .floppy, eyes: .sparkle, mouth: .cat, pattern: .hearts)),
        FigureDef(id: "sweet_captain", name: "Cupcake Captain", seriesID: "sweet", rarity: .rare,
                  flavor: "Commands the fridge. Throws out expired leftovers on sight.",
                  look: FigureLook(body: Color(hex: 0xD5C4FF), accent: Color(hex: 0xFF6F9F), ears: .antenna, eyes: .dot, mouth: .smile, hat: "birthday.cake.fill")),
        FigureDef(id: "sweet_parfait", name: "Parfait Princess", seriesID: "sweet", rarity: .epic,
                  flavor: "Layered, elegant, and expects the sink to be empty.",
                  look: FigureLook(body: Color(hex: 0xFF8FA8), belly: Color(hex: 0xFFF0F0), accent: Color(hex: 0xFFC94D), ears: .bunny, eyes: .sparkle, mouth: .tiny, pattern: .hearts, hat: "crown.fill")),
        FigureDef(id: "sweet_cosmic", name: "Cosmic Candy", seriesID: "sweet", rarity: .secret,
                  flavor: "Flavor: every flavor. Rarity: astronomically rare.",
                  look: FigureLook(body: Color(hex: 0xFFC6F0), accent: Color(hex: 0x7A5CFF), ears: .cat, eyes: .star, mouth: .open, held: "star.circle.fill", holo: true)),
    ]
}
