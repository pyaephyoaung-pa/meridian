// Renders a TTF to an AngelCode BMFont (text .fnt + one PNG page), the
// format the Connect IQ resource compiler imports. Used for the register
// label font on watches without vector fonts (see resources-labels-*).
//
//   swift tools/bmfont.swift <font.ttf> <px size> <chars> <out dir> <name>
//
// Glyphs are white with coverage in alpha (and in RGB, so either channel
// reads the same), one pixel apart, aligned to whole pixels.
import AppKit
import CoreText
import Foundation

let args = CommandLine.arguments
guard args.count == 6, let size = Double(args[2]) else {
    FileHandle.standardError.write("usage: bmfont.swift <font.ttf> <px> <chars> <outdir> <name>\n".data(using: .utf8)!)
    exit(1)
}
let fontURL = URL(fileURLWithPath: args[1]) as CFURL
let chars = Array(args[3])
let outDir = URL(fileURLWithPath: args[4])
let name = args[5]

guard let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor],
      let desc = descs.first else {
    FileHandle.standardError.write("cannot read font\n".data(using: .utf8)!)
    exit(1)
}
let font = CTFontCreateWithFontDescriptor(desc, CGFloat(size), nil)
let ascent = CTFontGetAscent(font)
let descent = CTFontGetDescent(font)
let base = Int(ceil(ascent))
let lineHeight = base + Int(ceil(descent))

struct Glyph {
    let ch: Character
    let glyph: CGGlyph
    let x0: Int, y0: Int, w: Int, h: Int   // pixel box, y up from the baseline
    let advance: Int
    var ax = 0, ay = 0                      // position in the atlas
}

var glyphs: [Glyph] = []
for ch in chars {
    var units = Array(String(ch).utf16)
    var g = [CGGlyph](repeating: 0, count: units.count)
    guard CTFontGetGlyphsForCharacters(font, &units, &g, units.count), g[0] != 0 else {
        FileHandle.standardError.write("no glyph for \(ch)\n".data(using: .utf8)!)
        exit(1)
    }
    var glyph = g[0]
    var box = CGRect.zero
    CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &box, 1)
    var adv = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &adv, 1)
    let x0 = Int(floor(box.minX)), y0 = Int(floor(box.minY))
    let w = box.isEmpty ? 0 : Int(ceil(box.maxX)) - x0
    let h = box.isEmpty ? 0 : Int(ceil(box.maxY)) - y0
    glyphs.append(Glyph(ch: ch, glyph: glyph, x0: x0, y0: y0, w: w, h: h,
                        advance: Int(adv.width.rounded())))
}

// Shelf-pack into a 256 px wide page
let pageW = 256
var x = 1, y = 1, rowH = 0
for i in glyphs.indices {
    if x + glyphs[i].w + 1 > pageW { x = 1; y += rowH + 1; rowH = 0 }
    glyphs[i].ax = x
    glyphs[i].ay = y
    x += glyphs[i].w + 1
    rowH = max(rowH, glyphs[i].h)
}
var pageH = 8
while pageH < y + rowH + 1 { pageH *= 2 }

// Coverage, drawn into an 8-bit gray context (y up)
let space = CGColorSpaceCreateDeviceGray()
guard let ctx = CGContext(data: nil, width: pageW, height: pageH, bitsPerComponent: 8,
                          bytesPerRow: pageW, space: space,
                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { exit(1) }
ctx.setFillColor(gray: 0, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
ctx.setFillColor(gray: 1, alpha: 1)
ctx.setShouldAntialias(true)
ctx.setShouldSmoothFonts(false)
ctx.setAllowsFontSubpixelPositioning(false)
for g in glyphs where g.w > 0 {
    // atlas top-left (ax, ay) -> CG bottom-left; place the pixel box there
    let boxBottom = pageH - g.ay - g.h
    var glyph = g.glyph
    var pos = CGPoint(x: CGFloat(g.ax - g.x0), y: CGFloat(boxBottom - g.y0))
    CTFontDrawGlyphs(font, &glyph, &pos, 1, ctx)
}
guard let gray = ctx.data?.bindMemory(to: UInt8.self, capacity: pageW * pageH) else { exit(1) }

// RGBA page: white-on-transparent with coverage in every channel
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pageW, pixelsHigh: pageH,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: pageW * 4, bitsPerPixel: 32)!
let px = rep.bitmapData!
for row in 0..<pageH {
    for col in 0..<pageW {
        // CG memory is top row first for a bitmap context
        let c = gray[row * pageW + col]
        let o = (row * pageW + col) * 4
        px[o] = c; px[o + 1] = c; px[o + 2] = c; px[o + 3] = c
    }
}
let pngName = "\(name)_0.png"
try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(pngName))

var fnt = "info face=\"\(name)\" size=\(Int(size)) bold=0 italic=0 charset=\"\" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n"
fnt += "common lineHeight=\(lineHeight) base=\(base) scaleW=\(pageW) scaleH=\(pageH) pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0\n"
fnt += "page id=0 file=\"\(pngName)\"\n"
fnt += "chars count=\(glyphs.count)\n"
for g in glyphs {
    let id = g.ch.unicodeScalars.first!.value
    let yoff = base - (g.y0 + g.h)
    fnt += "char id=\(id) x=\(g.ax) y=\(g.ay) width=\(g.w) height=\(g.h) xoffset=\(g.x0) yoffset=\(yoff) xadvance=\(g.advance) page=0 chnl=15\n"
}
try! fnt.write(to: outDir.appendingPathComponent("\(name).fnt"), atomically: true, encoding: .utf8)
print("\(name): \(glyphs.count) glyphs, line \(lineHeight), base \(base), page \(pageW)x\(pageH)")
