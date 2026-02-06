# BNF Meta-Grammar Specification

This document specifies the 10-rule BNF meta-grammar used for bootstrapping the Chalk::Bootstrap compiler.

## Source

Extracted from: https://gist.githubusercontent.com/perigrin/eb2b536c312b6fee3584bb0f7d97cde0/raw/af1e52bd340ce7b588a6c2fca4b0de141c74f8f9/cleanroom.md (§2.2)

## Grammar Rules

```bnf
# BNF Meta-Grammar

Grammar       ::= /(?:\s|#[^\n]*)*/ Rule+ ;
Rule          ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/ ;
Alternatives  ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence ;
Sequence      ::= Sequence_Element /(?:\s|#[^\n]*)+/ Sequence | Sequence_Element ;
Element       ::= Atom Quantifier? ;
Atom          ::= Identifier | InlineRegex ;
Quantifier    ::= /\*/ | /\+/ | /\?/ ;
Comment       ::= /#[^\n]*/ ;

# Terminals
Identifier    ::= /[A-Za-z_][A-Za-z_0-9]*/ ;
InlineRegex   ::= /\/(?:[^\/\\]|\\.)*\// ;
```

**Note**: The `Sequence` rule has been modified from the original to avoid naming collision with the `Sequence` nonterminal. The sequence element is now called `Sequence_Element` to maintain unambiguous naming.

## Rule Count

Total rules: 10 (Grammar, Rule, Alternatives, Sequence, Element, Atom, Quantifier, Comment, Identifier, InlineRegex)

## Quantifier Desugaring

The `*`, `+`, and `?` quantifiers are expanded during grammar compilation to helper rules:
- `X*` → deterministic helper rule for zero-or-more repetition
- `X+` → deterministic helper rule for one-or-more repetition
- `X?` → deterministic helper rule for optional element

This expansion increases effective rule count to ~12-16 rules during parsing.

## Terminal Patterns

All inline regex patterns (`/.../`) are anchored at `\G` during matching to implement scanless parsing.

The whitespace/comment pattern `/(?:\s|#[^\n]*)*` appears frequently and matches:
- Zero or more whitespace characters
- Zero or more line comments (# to end of line)

## Self-Hosting Property

This grammar is written in its own notation. After bootstrapping, the Chalk::Bootstrap compiler can parse and compile this grammar specification to generate a BNF recognizer.

## Validation Test

The generated recognizer must accept/reject identical inputs as the hand-written `Chalk::Grammar::BNF` recognizer for self-hosting validation to pass.
