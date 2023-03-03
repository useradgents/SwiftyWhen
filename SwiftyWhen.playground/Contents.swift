// SwiftyWhen.swift
// Implementing Kotlin's `when` in Swift with Result Builders, Autoclosures and Generics
// Published by Useradgents (article available on www.useradgents.com)
// Written by Cyrille Legrand, Head of Mobile
// March 3, 2023

import Foundation

// MARK: - Matching a single (default?) case

infix operator =>

func => <Input, Output> (input: Input, output: @escaping @autoclosure () -> Output) -> WhenCase<Input, Output> {
    WhenCase(input: input, output: output)
}
func => <Input, Output> (input: Input.Type, output: @escaping @autoclosure () -> Output) -> WhenCase<Input, Output> {
    WhenCase(input: nil, output: output)
}

struct WhenCase<Input, Output> {
    let input: Input? // optional to handle nil input for the default case
    let output: () -> Output
}

// MARK: - Grouping several cases

@resultBuilder
struct WhenCaseArrayBuilder<Input, Output> {
    static func buildBlock(_ components: WhenCase<Input, Output>...) -> [WhenCase<Input, Output>] {
        components
    }
}

// MARK: - Matching against a group of cases

func when <Input: Equatable, Output> (_ value: Input, @WhenCaseArrayBuilder<Input, Output> cases: () -> [WhenCase<Input, Output>]) -> Output {
    // Run the result builder to collect all the cases
    let allCases = cases()
    
    // Match against all cases having a value
    for c in allCases {
        if value == c.input {
            // Found a match! Evaluate the output and return it.
            return c.output()
        }
    }
    
    // If we reach here, no input matched value. If we have a default case, use it.
    if let defaultCase = allCases.first(where: { $0.input == nil }) {
        return defaultCase.output()
    }
    
    // If we reach here… there's nothing more we can do: it's because the developer
    // has not provided a default case. We'll just trigger a fatalError.
    fatalError("No default case implemented, write it as \(String(describing: Input.self)).self => default_value")
}

// MARK: - Play time!

extension Int {
    var spelledOut: String {
        when(self) {
            1 => "one"
            2 => "two"
            3 => "three"
            Int.self => "I can only count up to three, sorry."
        }
    }
}

print(2.spelledOut) // will print "two"
print(4.spelledOut) // will print "I can only count up to three, sorry."
