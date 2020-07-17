//
//  main.swift
//  USFMParser
//
//  Created by Chris Hulbert on 9/7/20.
//  Copyright © 2020 Chris. All rights reserved.
//

// This is for translating USFM bibles into a more machine-friendly format.
// To use: Download the USFM source from here: http://freebibleversion.org then unzip to ~/fbv
// Change your home folder below to suit.
// This is all very rough code, not optimised or tidy. Just enough to get the job done, then move onto more important things!

import Foundation

// All tags in FBV: ["f*", "ft", "toc3", "toc2", "mt1", "+it", "p", "h", "v", "c", "it", "f", "fr", "it*", "q1", "d", "toc1", "id", "+it*", "xt", "pi1"]
// +it is only used in footnotes. Seems to bend the rules a bit.

extension String.Element {
    var isUSFMWhitespace: Bool {
        return self==" " || self=="\t" || self=="\r" || self=="\n"
    }
}

enum InitialParsePart {
    case tag(String)
    case tagFinaliser(String) // Asterisk tag.
    case text(String)
}

/// Convert raw line to group things into tags and nontags.
func parseParts(fromLine line: String) -> [InitialParsePart] {
    var output: [InitialParsePart] = []
    
    enum State {
        case nothing
        case inTag(String)
        case text(String)
    }
    var state = State.nothing
    for c in line {
        switch state {
        case .nothing:
            if c=="\\" {
                state = .inTag("")
            } else {
                state = .text(String(c))
            }
            
        case .text(let accumulatedText):
            if c=="\\" { // Start tag.
                output.append(.text(accumulatedText))
                state = .inTag("")
            } else { // More text.
                state = .text(accumulatedText + String(c))
            }
                
        case .inTag(let accumulatedTag):
            if c.isUSFMWhitespace { // Tag ended.
                output.append(.tag(accumulatedTag))
                state = .nothing
            } else if c=="*" { // Tag ended as a 'end of tag'.
                output.append(.tagFinaliser(accumulatedTag))
                state = .nothing
            } else { // Tag continues.
                state = .inTag(accumulatedTag + String(c))
            }
        }
    }
    // Handle leftovers.
    switch state {
    case .nothing: break
    case .text(let t):
        output.append(.text(t))
    case .inTag(let t):
        output.append(.tag(t))
    }
    return output
}

struct FootnoteDetails {
    let symbol: String?
    let reference: String?
    let text: String
    init(symbol: String?, reference: String?, text: String) {
        self.symbol = symbol?.trimmingCharacters(in: .whitespaces)
        self.reference = reference?.trimmingCharacters(in: .whitespaces)
        self.text = text
    }
}

enum TextOrFootnote {
    case text(String)
    case italicText(String)
    case footnote(FootnoteDetails)
}

enum SecondaryParsePart {
    // once per file:
    case id(String, String?)
    case header(String)
    case toc1(String) // Table of contents long eg 'second corinthians'
    case toc2(String) // Toc short eg '2 corinthians'
    case toc3(String) // 'Book abbreviation' but only used for psalms
    case majorTitle(String)
    
    case poeticLineEmpty // FBV has a lot of empty '\q1' lines in psalms: Are they supposed to mean that the subsequent line is poetic?
    case poeticLine(String)
    case paraEmpty
    case paraWithText(String)
    case paraIndented(String?)
    case descriptiveTitle(String)
    case chapterNumber(Int)
    case simpleVerse(Int, String) // Verse with no footnotes.
    case complexVerse(Int, [TextOrFootnote])
    case complexPara([TextOrFootnote])
    case complexParaIndented([TextOrFootnote])
    case complexDescriptiveTitle([TextOrFootnote])
}

extension Array {
    var cdr: [Element] { // Safely returns the 'rest' after the first.
        guard count >= 2 else { return [] }
        return Array(suffix(from: 1))
    }
}

/// Tries for the simple case where it's just a tag, or a tag and text.
func tryParseSecondarySimpleCase(firstTag: String, rest: [InitialParsePart]) -> SecondaryParsePart? {
    var texts = ""
    var hasAnyOtherParts = false
    var hasAnyOtherTags = false
    for part in rest {
        hasAnyOtherParts = true
        if case .text(let t) = part {
            texts += t
        } else {
            hasAnyOtherTags = true
        }
    }
    if !hasAnyOtherParts {
        if firstTag=="p" {
            return SecondaryParsePart.paraEmpty
        } else if firstTag=="pi1" {
            return SecondaryParsePart.paraIndented(nil)
        } else if firstTag=="q1" {
            return SecondaryParsePart.poeticLineEmpty
        } else {
            //        return SecondaryParsePart.tagOnly(firstTag) // Eg '/p'
            return nil
        }
    } else if hasAnyOtherParts && !hasAnyOtherTags {
        if firstTag=="p" {
            return SecondaryParsePart.paraWithText(texts)
        } else if firstTag=="q1" {
            return SecondaryParsePart.poeticLine(texts)
        } else if firstTag=="pi1" {
            return SecondaryParsePart.paraIndented(texts)
        } else if firstTag=="d" {
            return SecondaryParsePart.descriptiveTitle(texts)
        } else if firstTag=="h" {
            return SecondaryParsePart.header(texts)
        } else if firstTag=="toc1" {
            return SecondaryParsePart.toc1(texts)
        } else if firstTag=="toc2" {
            return SecondaryParsePart.toc2(texts)
        } else if firstTag=="toc3" {
            return SecondaryParsePart.toc3(texts)
        } else if firstTag=="mt1" {
            return SecondaryParsePart.majorTitle(texts)
        } else if firstTag=="id" {
            let s = texts.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            if s.count == 1 {
                return SecondaryParsePart.id(String(s[0]), nil)
            } else if s.count == 2 {
                return SecondaryParsePart.id(String(s[0]), String(s[1]))
            } else {
                return nil
            }
        } else if firstTag == "c" {
            guard let c = Int(texts) else { return nil }
            return SecondaryParsePart.chapterNumber(c)
        } else {
            return nil
            //        return SecondaryParsePart.tagAndText(firstTag, texts)
        }
    } else {
        return nil // Complex case.
    }
}

// TODO ensure it keeps the whitespace at the end of a verse (except verses that have a para break next), so we don't have to add them between.
func tryParseSecondarySimpleVerseCase(firstTag: String, rest: [InitialParsePart]) -> SecondaryParsePart? {
    guard firstTag == "v" else { return nil }
    guard rest.count == 1 else { return nil }
    guard let part = rest.first else { return nil }
    guard case .text(let text) = part else { return nil }
    // T will be eg "2 who confirmed everything he saw concerning the word of God and the testimony"
    let split = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
    guard split.count == 2 else { return nil }
    guard let verse = Int(split[0]) else { return nil } // Not a number!
    return SecondaryParsePart.simpleVerse(verse, String(split[1]))
}

// Turn into: Verse/Para/Indented para pi1/Descriptive title d([
//.text(X),
//.footnote(symbol:, reference:, text:),
//.text(X),
func tryParseSecondaryComplexVerseCase(firstTag: String, rest: [InitialParsePart]) -> SecondaryParsePart? {
    var contents: [TextOrFootnote] = []

    enum State {
        case normal
        case inItalic
        case inFootnoteLookingForSymbol
        case inFootnoteLookingForTags
        case inFootnoteReference
        case inFootnoteText
    }
    var state = State.normal
    var footnoteSymbol: String?
    var footnoteReference: String?
    var footnoteText: String?
    for part in rest {
        switch state {
        case .normal:
            switch part {
            case .tag(let t):
                if t=="f" {
                    state = .inFootnoteLookingForSymbol
                    footnoteText = nil
                    footnoteReference = nil
                    footnoteSymbol = nil
                } else if t=="it" {
                    state = .inItalic
                } else {
                    return nil
                }
            case .tagFinaliser:
                return nil
            case .text(let t):
                contents.append(.text(t))
            }
            
        case .inItalic:
            switch part {
            case .tag:
                return nil

            case .tagFinaliser(let t): // TODO test with "\v 20 But Christ \it has\it* been raised from the dead, the firstfruits"
                if t=="it" {
                    state = .normal
                } else {
                    return nil
                }
                
            case .text(let t):
                contents.append(.italicText(t))
            }

            
        case .inFootnoteLookingForSymbol:
            switch part {
            case .tag: return nil
            case .tagFinaliser: return nil
            case .text(let t):
                footnoteSymbol = t // trim?
                state = .inFootnoteLookingForTags
            }
            
        case .inFootnoteLookingForTags:
            switch part {
            case .tag(let t):
                if t=="fr" {
                    state = .inFootnoteReference
                } else if t=="ft" {
                    state = .inFootnoteText
                } else {
                    return nil
                }
            case .tagFinaliser(let t):
                if t=="f" {
                    guard let ft = footnoteText else { return nil }
                    contents.append(.footnote(FootnoteDetails(symbol: footnoteSymbol, reference: footnoteReference, text: ft)))
                    footnoteText = nil
                    footnoteReference = nil
                    footnoteSymbol = nil
                    state = .normal
                } else {
                    return nil
                }
            case .text(let t):
                footnoteText = (footnoteText ?? "") + t // Shouldn't reaaally happen but its ok.
            }
            
        case .inFootnoteText:
            switch part {
            case .tag(let t):
                if t=="fr" {
                    state = .inFootnoteReference
                } else if t=="xt" {
                    continue // Ignore XT (cross reference) tags eg: \d For the music director. According to Mahalath. A psalm (maskil) of David.\f + \fr 53:0 \ft This psalm is almost identical to \xt Psalms 14.\f*
                } else if t=="it" || t=="+it" {
                    continue // Read through italics in footnotes. It only happens rarely so low priority to support it.
                } else {
                    return nil
                }
            case .tagFinaliser(let t):
                if t=="f" {
                    guard let ft = footnoteText else { return nil }
                    contents.append(.footnote(FootnoteDetails(symbol: footnoteSymbol, reference: footnoteReference, text: ft)))
                    footnoteText = nil
                    footnoteReference = nil
                    footnoteSymbol = nil
                    state = .normal
                } else if t=="it" || t=="+it" {
                    continue // Read through italics in footnotes. It only happens rarely so low priority to support it.
                } else {
                    return nil
                }
            case .text(let t):
                footnoteText = (footnoteText ?? "") + t
            }

        case .inFootnoteReference:
            switch part {
            case .tag(let t):
                if t=="ft" {
                    state = .inFootnoteText
                } else if t=="it" || t=="+it" {
                    continue // Read through italics in footnotes. It only happens rarely so low priority to support it.
                } else {
                    return nil
                }
            case .tagFinaliser(let t):
                if t=="f" {
                    guard let ft = footnoteText else { return nil }
                    contents.append(.footnote(FootnoteDetails(symbol: footnoteSymbol, reference: footnoteReference, text: ft)))
                    footnoteText = nil
                    footnoteReference = nil
                    footnoteSymbol = nil
                    state = .normal
                } else if t=="it" || t=="+it" {
                    continue // Read through italics in footnotes. It only happens rarely so low priority to support it.
                } else {
                    return nil
                }
            case .text(let t):
                footnoteReference = (footnoteReference ?? "") + t
            }

        }
    }
    switch firstTag {
    case "p": return .complexPara(contents)
    case "pi1": return .complexParaIndented(contents)
    case "d": return .complexDescriptiveTitle(contents)
    case "v":
        // Extract the verse number.
        guard let firstContent = contents.first else { return nil }
        guard case .text(let t) = firstContent else { return nil }
        let split = t.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard split.count == 2 else { return nil }
        guard let verse = Int(split[0]) else { return nil } // Not a number!
        let remainder = String(split[1])
        contents[0] = .text(remainder)
        return .complexVerse(verse, contents) // TODO test against \v 20 If you died with Christ to the religious demands that this world insists upon...
    default: return nil
    }
}

/// This goes through all the parts, and anything that is in the format '\x blah' (no \x* or other markers) gets grabbed as a 'whole element'.
func parseSecond(fromParts parts: [InitialParsePart], line: String) -> [SecondaryParsePart] {
    guard let first = parts.first else { return [] }
    let rest = parts.cdr
    // Try the cases that start with a tag.
    if case .tag(let tagName) = first {
        if let simple = tryParseSecondarySimpleCase(firstTag: tagName, rest: rest) {
            return [simple]
        }
        if let verse = tryParseSecondarySimpleVerseCase(firstTag: tagName, rest: rest) {
            return [verse]
        }
        if let complex = tryParseSecondaryComplexVerseCase(firstTag: tagName, rest: rest) {
            return [complex]
        }
    }
    // Only ones that make it here are \v, \d, \p, \pi1
    // These contain \it..\it*
    // or \f
    // or \f*
    // or \xt (within a \f)
    print(line)
    return []
}


struct ParaDetails {
    let contents: [TextOrFootnote]
    let isIndented: Bool
}

enum TertiaryPart {
    case poeticLine(String?)
    case para(ParaDetails)
    case verse(Int, [TextOrFootnote])
    case descriptiveTitle([TextOrFootnote])
}

struct TertiaryBook {
    let id: String // 2JN
    let longName: String // Second John
    let shortName: String // 2 John
    let chapters: [Chapter]
}

struct Chapter {
    let number: Int
    let content: [TertiaryPart]
}

// Final polishing stage :)
func tert(fromSecond parts: [SecondaryParsePart]) -> TertiaryBook {
    var id: String?
    var longName: String?
    var shortName: String?
    var chapters: [Chapter] = []
    var thisChapterNumber: Int = 0
    var content: [TertiaryPart] = []
    for part in parts {
        switch part {
        case .id(let i, _):
            id = i
        case .header(_):
            break // Ignore the header, is capitalised badly sometimes; TOC is just as good
        case .toc1(let t):
            longName = t
        case .toc2(let t):
            shortName = t
        case .toc3(_):
            break // Ignore, rarely used.
        case .majorTitle:
            break // Ignore, same as TOC
        case .poeticLineEmpty:
            content.append(.poeticLine(nil))
        case .poeticLine(let t):
            content.append(.poeticLine(t))
        case .paraEmpty:
            content.append(.para(ParaDetails(contents: [], isIndented: false)))
        case .paraWithText(let t):
            content.append(.para(ParaDetails(contents: [.text(t)], isIndented: false)))
        case .paraIndented(let t):
            if let t = t {
                content.append(.para(ParaDetails(contents: [.text(t)], isIndented: true)))
            } else {
                content.append(.para(ParaDetails(contents: [], isIndented: true)))
            }
        case .descriptiveTitle(let t):
            content.append(.descriptiveTitle([.text(t)]))
        case .chapterNumber(let n):
            if !content.isEmpty {
                chapters.append(Chapter(number: thisChapterNumber, content: content))
                content = []
            }
            thisChapterNumber = n
        case .simpleVerse(let n, let t):
            content.append(.verse(n, [.text(t)]))
        case .complexVerse(let n, let c):
            content.append(.verse(n, c))
        case .complexPara(let c):
            content.append(.para(ParaDetails(contents: c, isIndented: false)))
        case .complexParaIndented(let c):
            content.append(.para(ParaDetails(contents: c, isIndented: true)))
        case .complexDescriptiveTitle(let c):
            content.append(.descriptiveTitle(c))
        }
    }
    if !content.isEmpty {
        chapters.append(Chapter(number: thisChapterNumber, content: content))
    }
    return TertiaryBook(id: id ?? "MISSING",
                        longName: longName ?? "MISSING",
                        shortName: shortName ?? "MISSING",
                        chapters: chapters)
}

func convert(usfm: URL) {
    let d = try! Data(contentsOf: usfm)
    let s = String(data: d, encoding: .utf8)!
    let lines = s.components(separatedBy: "\n")
    var allSeconds: [SecondaryParsePart] = []
    for line in lines {
        guard !line.isEmpty else { continue }
        let parts = parseParts(fromLine: line)
        guard !parts.isEmpty else { continue }
        let secondParts = parseSecond(fromParts: parts, line: line)
        allSeconds.append(contentsOf: secondParts)
    }
    let book = tert(fromSecond: allSeconds)
    print(book)
    abort()
}

let folder = URL(fileURLWithPath: "/Users/chris/fbv")
let files = try! FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])
for file in files {
    guard file.pathExtension=="usfm" else { continue }
    convert(usfm: file)
}
print("Done")
