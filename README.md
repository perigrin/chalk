# Chalk

> But the Chalk was her world. She walked on it every day. She could feel its
> ancient life under her feet. The land was in her bones, just as Granny Aching
> had said. It was in her name, too; in the old language of the Nac Mac Feegle,
> her name sounded like “Land Under Wave,” and in the eye of her mind she’d
> walked in those deep prehistoric seas when the Chalk had been formed, in a
> million-year rain made of the shells of tiny creatures. She trod a land made of
> life, and breathed it in, and listened to it, and thought its thoughts for it.

&mdash; Terry Pratchett, _A Hat Full of Sky_

**Chalk** is a self-hosting parser written in modern Perl (5.42+), implementing
a scannerless generalized Earley parser with Leo optimization for
right-recursive grammars. The architecture centers on **semirings** for
compositional parse semantics (supporting Boolean recognition, precedence-based
disambiguation, IR generation, and type inference), a **grammar-driven
evaluation system** where BNF definitions map to custom semantic action
classes, and semantic scoring to select preferred parses from ambiguous
alternatives. The parser handles Perl's complex syntax through preprocessor
transformations (heredocs), lexeme-based terminal matching, and score-based
disambiguation.

The system uses a modular pipeline: BNF grammar → Earley parser → semiring
evaluation → semantic output (IR or type-checked code). Key optimizations
include Leo items for deterministic right-recursion chains, nullable symbol
pre-computation, and indexed waiting sets for efficient completion operations.
The codebase leverages Perl's experimental class syntax and operator
overloading for algebraic semiring operations (`+` for choice combining scores,
`*` for sequencing), enabling practical self-compilation.

## Features

* Scannerless generalized Earley parser with Leo optimization
* [Sea of Nodes](https://en.wikipedia.org/wiki/Sea_of_nodes) Intermediate Representation
* Compositional semiring-based parse evaluation
* Grammar-driven semantic actions via custom rule classes

## License

This project is under the [Artistic License](https://opensource.org/licenses/artistic-license-2.0).
