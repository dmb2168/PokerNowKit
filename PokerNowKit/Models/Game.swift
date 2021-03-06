//
//  Game.swift
//  PNReplay
//
//  Created by PJ Gray on 5/25/20.
//  Copyright © 2020 Say Goodnight Software. All rights reserved.
//

import Foundation
import CryptoSwift

public class Game: NSObject {

    var debugHandAction: Bool = false
    var showErrors: Bool = false
    
    var players: [Player] = []
    public var hands: [Hand] = []
    var currentHand: Hand?

    var overflowLogDealerId: String?

    public init(rows: [[String:String]]) {
        super.init()

        if self.isSupportedLog(at: rows.reversed().first?["at"]) {
            for row in rows.reversed() {
                if row["entry"]?.starts(with: "The player ") ?? false {
                    self.parsePlayerLine(msg: row["entry"])
                } else if row["entry"]?.starts(with: "The admin ") ?? false {
                    self.parseAdminLine(msg: row["entry"])
                } else {
                    self.parseHandLine(msg: row["entry"], at: row["at"], order: row["order"])
                }

            }
        } else {
            print("Unsupported log format: the PokerNow.club file format has changed since this log was generated")
        }
    }
        
    private func isSupportedLog(at: String?) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let date = formatter.date(from: at ?? "") ?? Date()
        let oldestSupportedLog = Date(timeIntervalSince1970: 1594731595)
        
        return date > oldestSupportedLog
    }
    
    private func resetPotEquity() {
        // reset previous calls
        var players : [Player] = []
        for var player in self.players {
            player.existingPotEquity = 0
            players.append(player)
        }
        self.players = players
    }
    
    private func parseHandLine(msg: String?, at: String?, order: String? ) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let date = formatter.date(from: at ?? "")
        
        if msg?.starts(with: "-- starting hand ") ?? false {
            self.resetPotEquity()

            let startingHandComponents = msg?.components(separatedBy: " (dealer: \"")
            let unparsedDealer = startingHandComponents?.last?.replacingOccurrences(of: "\") --", with: "")
            
            // for legacy logs
            var dealerSeparator = " @ "
            if unparsedDealer?.contains(" # ") ?? false {
                dealerSeparator = " # "
            }

            let dealerNameIdArray = unparsedDealer?.components(separatedBy: dealerSeparator)
            if let dealer = self.players.filter({$0.id == dealerNameIdArray?.last}).first {
                let hand = Hand()

                let handIdHex = String("\(dealer.id ?? "error")-\(date?.timeIntervalSince1970 ?? 0)".md5().bytes.toHexString().prefix(15))
                var hexInt: UInt64 = 0
                let scanner = Scanner(string: handIdHex)
                scanner.scanHexInt64(&hexInt)
                hand.id = hexInt
                
                hand.date = date
                hand.dealer = dealer
                hand.players = self.players.filter({$0.sitting == true})
                self.currentHand = hand
                self.hands.append(hand)
            } else if msg?.contains("dead button") ?? false {
                let hand = Hand()

                let handIdHex = String("deadbutton-\(date?.timeIntervalSince1970 ?? 0)".md5().bytes.toHexString().prefix(15))
                var hexInt: UInt64 = 0
                let scanner = Scanner(string: handIdHex)
                scanner.scanHexInt64(&hexInt)
                hand.id = hexInt
                
                hand.date = date
                hand.dealer = nil
                hand.players = self.players.filter({$0.sitting == true})
                self.currentHand = hand
                self.hands.append(hand)
            } else {
                // overflow log scenario
                let hand = Hand()
                self.overflowLogDealerId = dealerNameIdArray?.last
                let handIdHex = String("\(self.overflowLogDealerId ?? "error")-\(date?.timeIntervalSince1970 ?? 0)".md5().bytes.toHexString().prefix(15))
                var hexInt: UInt64 = 0
                let scanner = Scanner(string: handIdHex)
                scanner.scanHexInt64(&hexInt)
                hand.id = hexInt
                
                hand.date = date
                self.currentHand = hand
                self.hands.append(hand)
            }
        } else if msg?.starts(with: "-- ending hand ") ?? false {
            if debugHandAction {
                print("----")
            }
        } else if msg?.starts(with: "Player stacks") ?? false {
            let playersWithStacks = msg?.replacingOccurrences(of: "Player stacks: ", with: "").components(separatedBy: " | ")
            
            // This should only do stuff in an overflow log situation
            for playerWithStack in playersWithStacks ?? [] {
                let seatNumber = playerWithStack.components(separatedBy: " ").first
                let playerWithStackNoSeat = playerWithStack.replacingOccurrences(of: "\(seatNumber ?? "") ", with: "")
                let seatNumberInt = (Int(seatNumber?.replacingOccurrences(of: "#", with: "") ?? "0") ?? 0)
                
                let nameIdArray = playerWithStackNoSeat.components(separatedBy: "\" ").first?.replacingOccurrences(of: "\"", with: "").components(separatedBy: " @ ")
                let stackSize = playerWithStack.components(separatedBy: "\" (").last?.replacingOccurrences(of: ")", with: "")
                
                if self.players.filter({$0.id == nameIdArray?.last}).count == 0 {
                    let player = Player(admin: false, id: nameIdArray?.last, stack: Double(stackSize ?? "0.0") ?? 0, name: nameIdArray?.first)
                    self.players.append(player)
                    
                    self.currentHand?.seats.append(Seat(player: player, summary: "\(player.name ?? "Unknown") didn't show and lost", preFlopBet: false, number: seatNumberInt))
                } else if self.players.filter({$0.id == nameIdArray?.last}).count == 1 {
                    let player = self.players.filter({$0.id == nameIdArray?.last}).first
                    self.currentHand?.seats.append(Seat(player: player, summary: "\(player?.name ?? "Unknown") didn't show and lost", preFlopBet: false, number: seatNumberInt))
                }
            }
                        
            if self.currentHand?.players.count == 0 {
                self.currentHand?.players = self.players.filter({$0.sitting == true})
                if let dealer = self.players.filter({$0.id == self.overflowLogDealerId}).first {
                    self.currentHand?.dealer = dealer
                }
            }
        } else if msg?.starts(with: "Your hand is ") ?? false {
            self.currentHand?.hole = msg?.replacingOccurrences(of: "Your hand is ", with: "").components(separatedBy: ", ").map({
                return EmojiCard(rawValue: $0)?.emojiFlip ?? .error
            })

            if debugHandAction {
                print("#\(self.currentHand?.id ?? 0) - hole cards: \(self.currentHand?.hole?.map({$0.rawValue}) ?? [])")
            }
        } else if msg?.starts(with: "Flop") ?? false {
            self.resetPotEquity()
            self.currentHand?.uncalledBet = 0.0

            let line = msg?.slice(from: "[", to: "]")
            self.currentHand?.flop = line?.replacingOccurrences(of: "Flop: ", with: "").components(separatedBy: ", ").map({
                return EmojiCard(rawValue: $0)?.emojiFlip ?? .error
            })
            
            if debugHandAction {
                print("#\(self.currentHand?.id ?? 0) - flop: \(self.currentHand?.flop?.map({$0.rawValue}) ?? [])")
            }

        } else if msg?.starts(with: "Turn") ?? false {
            self.resetPotEquity()
            self.currentHand?.uncalledBet = 0.0

            let line = msg?.slice(from: "[", to: "]")
            self.currentHand?.turn = EmojiCard(rawValue: line?.replacingOccurrences(of: "Turn: ", with: "") ?? "error")?.emojiFlip ?? .error

            if debugHandAction {
                print("#\(self.currentHand?.id ?? 0) - turn: \(self.currentHand?.turn?.rawValue ?? "?")")
            }

        } else if msg?.starts(with: "River") ?? false {
            self.resetPotEquity()
            self.currentHand?.uncalledBet = 0.0

            let line = msg?.slice(from: "[", to: "]")
            self.currentHand?.river = EmojiCard(rawValue: line?.replacingOccurrences(of: "River: ", with: "") ?? "error")?.emojiFlip ?? .error

            if debugHandAction {
                print("#\(self.currentHand?.id ?? 0) - river: \(self.currentHand?.river?.rawValue ?? "?")")
            }

        } else {
            let nameIdArray = msg?.components(separatedBy: "\" ").first?.components(separatedBy: " @ ")
            if var player = self.players.filter({$0.id == nameIdArray?.last}).first {
                self.players.removeAll(where: {$0.id == nameIdArray?.last})
                
                if msg?.contains("big blind") ?? false {
                    let bigBlindSize = Double(msg?.components(separatedBy: "big blind of ").last ?? "0.0") ?? 0.0
                    self.currentHand?.bigBlindSize = bigBlindSize
                    self.currentHand?.pot = (self.currentHand?.pot ?? 0.0) + bigBlindSize
                    self.currentHand?.uncalledBet = bigBlindSize
                    self.currentHand?.bigBlind.append(player)

                    player.existingPotEquity = bigBlindSize
                    if debugHandAction {
                        print("#\(self.currentHand?.id ?? 0) - \(player.name ?? "Unknown Player") posts big \(bigBlindSize)  (Pot: \(self.currentHand?.pot ?? 0.0))")
                    }
                }

                if msg?.contains("small blind") ?? false {
                    let smallBlindSize = Double(msg?.components(separatedBy: "small blind of ").last ?? "0.0") ?? 0.0
                    self.currentHand?.smallBlindSize = smallBlindSize
                    if msg?.contains("missing") ?? false {
                        self.currentHand?.missingSmallBlinds.append(player)
                    } else {
                        self.currentHand?.smallBlind = player
                        player.existingPotEquity = smallBlindSize
                    }
                    
                    self.currentHand?.pot = (self.currentHand?.pot ?? 0.0) + smallBlindSize
                    if debugHandAction {
                        print("#\(self.currentHand?.id ?? 0) - \(player.name ?? "Unknown Player") posts small \(smallBlindSize)  (Pot: \(self.currentHand?.pot ?? 0.0))")
                    }
                }

                if msg?.contains("posts a straddle") ?? false {
                    let straddleSize = Double(msg?.components(separatedBy: "of ").last ?? "0.0") ?? 0.0
                    self.currentHand?.pot = (self.currentHand?.pot ?? 0.0) + straddleSize - player.existingPotEquity
                    self.currentHand?.uncalledBet = straddleSize - (self.currentHand?.uncalledBet ?? 0.0)

                    player.existingPotEquity = straddleSize

                    if debugHandAction {
                        print("#\(self.currentHand?.id ?? 0) - \(player.name ?? "Unknown Player") straddles \(straddleSize)  (Pot: \(self.currentHand?.pot ?? 0.0))")
                    }
                }

                if msg?.contains("raises") ?? false {
                    let raiseSize = Double(msg?.components(separatedBy: "with ").last ?? "0") ?? 0.0
                    self.currentHand?.pot = (self.currentHand?.pot ?? 0.0) + raiseSize - player.existingPotEquity
                    self.currentHand?.uncalledBet = raiseSize - (self.currentHand?.uncalledBet ?? 0.0)

                    player.existingPotEquity = raiseSize

                    if debugHandAction {
                        print("#\(self.currentHand?.id ?? 0) - \(player.name ?? "Unknown Player") raises \(raiseSize)  (Pot: \(self.currentHand?.pot ?? 0.0))")
                    }
                }

                if msg?.contains("calls") ?? false {
                    let callSize = Double(msg?.components(separatedBy: "with ").last ?? "0.0") ?? 0.0
                    self.currentHand?.pot = (self.currentHand?.pot ?? 0.0) + callSize - player.existingPotEquity
                    if (self.currentHand?.uncalledBet ?? 0.0) == 0.0 {
                        self.currentHand?.uncalledBet = callSize
                    }

                    player.existingPotEquity = callSize

                    if debugHandAction {
                        print("#\(self.currentHand?.id ?? 0) - \(player.name ?? "Unknown Player") calls \(callSize)  (Pot: \(self.currentHand?.pot ?? 0.0))")
                    }
                }
                
                if msg?.contains("checks") ?? false {
                    if debugHandAction {
                        print("#\(self.currentHand?.id ?? 0) - \(player.name ?? "Unknown Player") checks  (Pot: \(self.currentHand?.pot ?? 0.0))")
                    }
                }

                if msg?.contains("folds") ?? false {
                    if debugHandAction {
                        print("#\(self.currentHand?.id ?? 0) - \(player.name ?? "Unknown Player") folds  (Pot: \(self.currentHand?.pot ?? 0.0))")
                    }
                }

                self.players.append(player)
            }
        }
        self.currentHand?.lines.append(msg ?? "unknown line")
    }
    
    private func parseAdminLine(msg: String?) {
        
        if msg?.contains("approved") ?? false {
            let nameIdArray = msg?.replacingOccurrences(of: "The admin approved the player \"", with: "").split(separator: "\"").first?.components(separatedBy: " @ ")
            if self.players.filter({$0.id == nameIdArray?.last}).count != 1 {
                let startingStackSize = Double(msg?.components(separatedBy: "with a stack of ").last?.replacingOccurrences(of: ".", with: "") ?? "0.0") ?? 0.0
                let player = Player(admin: false, id: nameIdArray?.last, stack: startingStackSize, name: nameIdArray?.first)
                self.players.append(player)
            } else {
                // approval of player already in game?  error case?
                if var player = self.players.filter({$0.id == nameIdArray?.last}).first {
                    self.players.removeAll(where: {$0.id == nameIdArray?.last})
                    player.sitting = true
                    let startingStackSize = Double(msg?.components(separatedBy: "with a stack of ").last?.replacingOccurrences(of: ".", with: "") ?? "0.0") ?? 0.0
                    player.stack = startingStackSize

                    self.players.append(player)
                }
            }
        }
    }
    
    private func parsePlayerLine(msg: String?) {

        let nameIdArray = msg?.replacingOccurrences(of: "The player \"", with: "").split(separator: "\"").first?.components(separatedBy: " @ ")

        if self.players.filter({$0.id == nameIdArray?.last}).count != 1 {
            let player = Player(admin: false, id: nameIdArray?.last, stack: 0.0, name: nameIdArray?.first)
            self.players.append(player)
        }

        if var player = self.players.filter({$0.id == nameIdArray?.last}).first {

            player.name = nameIdArray?.first

            self.players.removeAll(where: {$0.id == nameIdArray?.last})
            
            if msg?.contains("quits the game") ?? false {
                player.sitting = false
            }

            if msg?.contains("created the game with a stack of") ?? false {
                player.admin = true
                player.creator = true
            }

            if msg?.contains("stand up") ?? false {
                player.sitting = false
            }

            if msg?.contains("sit back with the stack of") ?? false {
                player.sitting = true
            }

            if msg?.contains("passed the room ownership to") ?? false {
                let newAdmin = msg?.components(separatedBy: "passed the room ownership to ").last?.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: ".", with: "")
                
                let newAdminNameIdArray = newAdmin?.components(separatedBy: " @ ")
        
                if var newAdminPlayer = self.players.filter({$0.id == newAdminNameIdArray?.last}).first {
                    player.admin = false
                    newAdminPlayer.admin = true
                } else {
                    if self.showErrors {
                        print("ERROR: could not find player to make admin: \(newAdminNameIdArray?.last ?? "")")
                    }
                }
            }

            self.players.append(player)

        } else {
            if self.showErrors {
                print("ERROR: could not find player: \(nameIdArray?.last ?? "")")
            }
        }
    }
}
