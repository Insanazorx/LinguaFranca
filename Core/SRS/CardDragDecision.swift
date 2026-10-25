import Foundation

/// Only a deliberate horizontal release rates a card. Vertical drags remain free movement.
public enum CardDragDecision {
    public static func rating(x:Double,y:Double,cardWidth:Double) -> ReviewRating? {
        guard x.isFinite,y.isFinite,cardWidth.isFinite,cardWidth > 0 else { return nil }
        let threshold=max(80,min(140,cardWidth*0.28))
        guard abs(x) >= threshold,abs(x) > abs(y)*0.9 else { return nil }
        return x > 0 ? .good : .again
    }
}
