// Tests/PurahCoreTests/LaTeXMathRendererTests.swift
import Foundation
import Testing
@testable import PurahCore

@Suite("LaTeX Math")
struct LaTeXMathRendererTests {

    @Test("A display formula becomes readable text")
    func testDisplayFormula() {
        let source = #"$$F(\omega)=\int f(t)\,e^{-i\omega t}\,dt$$"#
        #expect(LaTeXMathRenderer.render(source) == "F(ω)=∫ f(t) e^(-iω t) dt")
    }

    @Test("An inline formula keeps its surrounding prose")
    func testInlineFormula() {
        let source = #"那个 $e^{-i\omega t}$ 不是神秘东西"#
        #expect(LaTeXMathRenderer.render(source) == "那个 e^(-iω t) 不是神秘东西")
    }

    @Test("Superscripts and subscripts that Unicode can carry are carried")
    func testSuperAndSubscript() {
        #expect(LaTeXMathRenderer.convert(#"\sum_{i=1}^{n} x^2"#) == "∑ᵢ₌₁ⁿ x²")
    }

    @Test("A fraction becomes a division, parenthesised when it has to be")
    func testFraction() {
        #expect(LaTeXMathRenderer.convert(#"\frac{a-b}{c}"#) == "(a-b)/c")
        #expect(LaTeXMathRenderer.convert(#"\frac{1}{2}"#) == "1/2")
    }

    @Test("Roots, text and accents")
    func testMisc() {
        #expect(LaTeXMathRenderer.convert(#"\sqrt{x^2+y^2}"#) == "√(x²+y²)")
        #expect(LaTeXMathRenderer.convert(#"\text{if } x"#) == "if x")
        #expect(LaTeXMathRenderer.convert(#"\hat{y}"#) == "y\u{0302}")
    }

    @Test("Money is not an equation")
    func testCurrencyUntouched() {
        let source = "It costs $5 and $10 more."
        #expect(LaTeXMathRenderer.render(source) == source)
    }

    @Test("Code is not maths")
    func testCodeUntouched() {
        let fenced = """
        ```
        echo $HOME && awk '$1 > $2'
        ```
        """
        #expect(LaTeXMathRenderer.render(fenced) == fenced)

        let inline = "Run `awk '$1 > $2'` on it"
        #expect(LaTeXMathRenderer.render(inline) == inline)
    }

    @Test("An unbalanced dollar is left alone")
    func testUnbalanced() {
        #expect(LaTeXMathRenderer.render("a $x + y") == "a $x + y")
    }
}
