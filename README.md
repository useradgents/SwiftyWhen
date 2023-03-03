# Implementing Kotlin's `when` in Swift with Result Builders, Autoclosures and Generics

How many time does a Swift developer spend on writing this kind of code?

```swift
enum Theme {
	case red
	case green
	case blue
	
	var color: UIColor {
		switch self {
			case .red: return UIColor(named: "theme_red")
			case .green: return UIColor(named: "theme_green")
			case .blue: return UIColor(named: "theme_blue")
		}
	}
}
```

If [this Swift-Evolution idea](https://forums.swift.org/t/evolution-idea-implicit-return-in-single-line-switch-cases/59684) ever comes out, it will be a little shorter as we will be able to omit the `return` in every `case`.

In the meantime, we can stand on the shoulders of our fellow Android developers, and realize that Kotlin's `when` (the equivalent to Swift's `switch`) has implicit return statements:

```kotlin
return when(self) {
	1 -> "one"
	2 -> "two"
	3 -> "three"
}
```

But by now, you may have heard of [Result Builders](https://developer.apple.com/videos/play/wwdc2021/10253/), one of the awesome features introduced in Swift 5.4 that powers SwiftUI. What if we could leverage the capabilities of a Result Builder to simplify the way we write switch-cases, so that it resembles Kotlin? Something like...

```swift
var color: UIColor {
	when(self) {
		.red   => UIColor(named: "theme_red")
		.green => UIColor(named: "theme_green")
		.blue  => UIColor(named: "theme_blue")
	}
}
```

We'll just use the double arrow `=>` operator, as the single arrow `->` is already used for function signatures.

Let's crack this up!

## What we'll need to solve

We want a way to :

- express the relation between a single precise case (or a default case) and the output value returned
- group all possible cases into a list
- match all these possible cases against an input value, and extract the corresponding output value.

As we want our code to work on any type (input and output likewise), we'll also use generics.

## 1. Relate a case to its output value

Relating a case to its value will be done with a custom, generic `=>` operator:

```
infix operator =>

public func => <Input, Output> (input: Input, output: Output) -> ... { ... }
```

Before even implementing the body of this function, we'll need to think about its parameters and return type.

This function is not intended to be evaluated immediately, but only when the `when()` will execute. So we'll just need to store its parameters for future use, inside a `Struct` with two properties (input and output).

Moreover, the output must not be evaluated right now: like a real `switch/case`, only the matching case must be evaluated. We could provide the output as a closure that we'll only call if the match succeeds, but this is the perfect job for an `@autoclosure`: it allows the developer to write "plain" code that will automatically be wrapped in a closure by the Swift compiler.

So we need to change the `output` parameter to an `@autoclosure`, and store both the input and the output closure into a `Struct`:

```swift
struct WhenCase<Input, Output> {
    let input: Input
    let output: () -> Output
}

func => <Input, Output> (input: Input, output: @escaping @autoclosure () -> Output) -> WhenCase<Input, Output> {
    WhenCase(input: input, output: output)
}
```

Now that we have a way to store the association between a case and its value, we have to create the list of cases.

## 2. Group cases into a list

That's where Result Builders comes into play: we'll create one that automatically groups several lines of `WhenCase`s (written as `input => output`) into a single array of `WhenCases`.

It's really easy for simple arrays, even though the declaration is cryptic:

```swift
@resultBuilder 
struct WhenCaseArrayBuilder<Input, Output> {
    static func buildBlock(_ components: WhenCase<Input, Output>...) -> [WhenCase<Input, Output>] {
        components
    }
}
```

The `buildBlock` function is the only required function of a Result Builder, it takes a variadic list of whatever, and maps it to an array of whatever.

So: our result builder collects every encountered `WhenCase`, and returns all of them as an array. We'll then be able to feed that array to the final function that actually performs the match.

## 3. Perform the match

This is a regular global function with a trailing closure, that will match an `Equatable` input value against all possible cases. The only complex part is that our trailing closure will be build with our Result Builder, so it needs the correct annotation:

```swift
func when <Input: Equatable, Output> (_ value: Input, @WhenCaseArrayBuilder<Input, Output> cases: () -> [WhenCase<Input, Output>]) -> Output {
    // Call the result builder to collect all the cases
    let allCases = cases()
    
    // Match against each
    for c in allCases {
        if value == c.input {
            return c.output() 
        }
    }
}
```

The implementation is straightforward: call the result builder to collect all the cases; then take each case in order, see if the input matches, then evaluate and return the output.

But, there's a catch: we don't have a "default" value to return in case nothing matches. This code will not compile as-is.

In order to replicate the `default: return default_value` case, we'll need a way to signal a wildcard, or empty, input to our `WhenCases`.

We'll use the `nil` value for this, so we have to slightly modify `WhenCase`:

```swift
struct WhenCase<Input, Output> {
	let input: Input? // optional to handle nil input for the default case
	let output: () -> Output
}
```

But there's no way we could write `nil => "default_value"`: the compiler can infer the type of the `Output` value (here, `String`), but `nil` has no type so Swift will complain that the `Input` type is unspecified.

That's why we propose to write default cases as `Int.self => "default_value"` : the `Int.self` conveys the meaning of "any other `Int`" and the presence of a concrete type makes the compiler happy.

So we'll need to write a second version of our `=>` operator with a different signature, to handle passing a type instead of an actual value. Below the first `=>` implementation, add another one:

```swift
func => <Input, Output> (input: Input.Type, output: @escaping @autoclosure () -> Output) -> WhenCase<Input, Output> {
    WhenCase(input: nil, output: output)
}
```

We also need to update our `when` function to handle the default case:

```swift
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
```

## 4. Profit!

Now we can test our code:

```
enum Theme {
	case red
	case green
	case blue
	case yellow
	
	var color: UIColor {
		when(self) {
			.red       => UIColor(named: "theme_red")
			.green     => UIColor(named: "theme_green")
			.blue      => UIColor(named: "theme_blue")
			Theme.self => UIColor(named: "theme_unknown")
		}
	}
}

label1.color = Theme.red.color    // UIColor named "theme_red"
label2.color = Theme.yellow.color // UIColor named "theme_unknown"
```

Bottom line: this is all just syntactic sugar, still misses many of the power of Swift's or Kotlin's pattern matching, but it's a perfect example to learn about bringing together complex techniques into an working and usable solution. You may not end up using this in production code, because it brings a slight overhead at runtime in order to just use an alternative syntax to something that already exists; but Result Builders, autoclosures, and generics are such powerful tools when combined that their applications are multiple.

Download the full Xcode playground [on GitHub](https://github.org/useradgents/SwiftyWhen)

References and documentation:

- Result Builders at [HackingWithSwift](https://www.hackingwithswift.com/swift/5.4/result-builders)
- Autoclosures at [Swift by Sundell](https://www.swiftbysundell.com/articles/using-autoclosure-when-designing-swift-apis/)
- Generics at [swift.org](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/generics/)


— Cyrille Legrand, Head of Mobile, Useradgents // March 3, 2023