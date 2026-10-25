import Foundation
import NaturalLanguage

public struct SpeechTokenTime:Sendable {
    public let text:String
    public let start:TimeInterval
    public init(text:String,start:TimeInterval) {self.text=text;self.start=start}
}
public struct SpeechWordTime:Sendable,Equatable {
    public let range:UTF16Span
    public let start,end:TimeInterval
}
public struct SpeechWordAlignment:Sendable {
    public let words:[SpeechWordTime]
    public let coverage:Double
    public static func align(text:String,tokens:[SpeechTokenTime],duration:TimeInterval) -> Self {
        guard duration.isFinite,duration>0,text.count<=1400,tokens.count<=2000 else{return .init(words:[],coverage:0)}
        struct Heard {var text:String;let start:Double}
        var heard:[Heard]=[]
        for token in tokens where token.start.isFinite && token.start>=0 && token.start<duration && !token.text.hasPrefix("<") {
            if token.text.hasPrefix("▁") || token.text.hasPrefix(" ") || heard.isEmpty {
                heard.append(.init(text:token.text.replacingOccurrences(of:"▁",with:" ").trimmingCharacters(in:.whitespaces),start:token.start))
            } else {heard[heard.count-1].text+=token.text}
        }
        heard=heard.filter{!key($0.text).isEmpty}
        guard !heard.isEmpty else{return .init(words:[],coverage:0)}
        struct Reference {let text:String;let range:UTF16Span}
        var reference:[Reference]=[]
        let tokenizer=NLTokenizer(unit:.word);tokenizer.string=text;tokenizer.setLanguage(.russian)
        let formatter=NumberFormatter();formatter.locale=Locale(identifier:"ru_RU");formatter.numberStyle = .spellOut
        var originalCount=0
        tokenizer.enumerateTokens(in:text.startIndex..<text.endIndex) {range,_ in
            let value=String(text[range]);guard value.contains(where:{$0.isLetter || $0.isNumber}) else{return true}
            let ns=NSRange(range,in:text),span=UTF16Span(location:ns.location,length:ns.length)
            originalCount+=1
            if let number=Int(value),number>=0,number<=1_000_000,let spelling=formatter.string(from:NSNumber(value:number)) {
                reference+=spelling.split(whereSeparator:{$0.isWhitespace || $0=="-"}).map{Reference(text:key(String($0)),range:span)}
            } else {reference.append(.init(text:key(value),range:span))}
            return true
        }
        guard !reference.isEmpty,reference.count<=500,heard.count<=600 else{return .init(words:[],coverage:0)}
        let m=reference.count,n=heard.count,columns=n+1
        var costs=Array(repeating:Double.zero,count:(m+1)*(n+1)),steps=Array(repeating:UInt8.zero,count:(m+1)*(n+1))
        for i in 1...m {costs[i*columns]=Double(i);steps[i*columns]=1}
        for j in 1...n {costs[j]=Double(j);steps[j]=2}
        func similar(_ a:String,_ b:String)->Bool {
            if a==b {return true}
            let aa=Array(a),bb=Array(b),limit=Int(Double(max(aa.count,bb.count))*0.25)
            guard limit>0,abs(aa.count-bb.count)<=limit else{return false}
            var previous=Array(0...bb.count)
            for (i,x) in aa.enumerated() {
                var row=[i+1]+Array(repeating:0,count:bb.count)
                for (j,y) in bb.enumerated() {row[j+1]=min(previous[j+1]+1,row[j]+1,previous[j]+(x==y ? 0:1))}
                previous=row
            }
            return previous[bb.count]<=limit
        }
        for i in 1...m {
            for j in 1...n {
                let a=reference[i-1].text,b=key(heard[j-1].text)
                let match=a==b ? 0.0:similar(a,b) ? 0.65:2.1
                let options=[costs[(i-1)*columns+j-1]+match,costs[(i-1)*columns+j]+1,costs[i*columns+j-1]+1]
                let direction=options.indices.min{options[$0]<options[$1]}!
                costs[i*columns+j]=options[direction];steps[i*columns+j]=UInt8(direction)
            }
        }
        var i=m,j=n,matches:[(Int,Int)]=[]
        while i>0 || j>0 {
            switch steps[i*columns+j] {
            case 0:
                if i>0,j>0,similar(reference[i-1].text,key(heard[j-1].text)) {matches.append((i-1,j-1))}
                i-=1;j-=1
            case 1:i-=1
            default:j-=1
            }
        }
        var words:[SpeechWordTime]=[]
        for (r,h) in matches.reversed() {
            let start=heard[h].start,end=h+1<heard.count ? heard[h+1].start:duration
            guard end>start else {continue}
            let range=reference[r].range
            if let last=words.last,last.range==range {words[words.count-1] = .init(range:range,start:last.start,end:max(last.end,end))}
            else {words.append(.init(range:range,start:start,end:end))}
        }
        let coverage=Double(Set(words.map{$0.range.location}).count)/Double(max(1,originalCount))
        return .init(words:words,coverage:coverage)
    }
    private static func key(_ text:String)->String {
        text.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"ru_RU"))
            .replacingOccurrences(of:"ё",with:"е").filter{$0.isLetter || $0.isNumber}
    }
}

public protocol SpeechWordAligningService:Sendable {
    func align(audio:SpeechAudio,text:String) async throws -> SpeechWordAlignment
    func unload() async
}
