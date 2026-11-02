// CoreGraphics Swift geometry members under Darling.
import CoreGraphics

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
check(rect.minX == 10 && rect.maxX == 40, "horizontal bounds")
check(rect.minY == 20 && rect.maxY == 60, "vertical bounds")
check(rect.contains(CGPoint(x: 15, y: 25)), "point containment")
check(!rect.contains(CGPoint(x: 40, y: 25)), "maximum edge is excluded")

let transform = CGAffineTransform.identity.translatedBy(x: 3, y: 4)
check(transform.tx == 3 && transform.ty == 4, "translation")
check(!transform.isIdentity, "translated transform is not identity")
