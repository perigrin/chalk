# ABOUTME: Semantic action for QualifiedIdentifier - handles package-qualified names
# ABOUTME: Returns simple identifier or builds qualified name like "Foo::Bar::Baz"

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::QualifiedIdentifier :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my @children = $context->children->@*;

        # QualifiedIdentifier -> Identifier (simple case)
        if (@children == 1) {
            return $context->child(0);
        }

        # QualifiedIdentifier -> Identifier '::' QualifiedIdentifier
        # Build qualified name: "Foo::Bar::Baz"
        if (@children == 3) {
            my $first = $context->child(0);  # First identifier
            my $sep   = $context->child(1);  # '::'
            my $rest  = $context->child(2);  # Rest of qualified name

            return $first . $sep . $rest;
        }

        # Shouldn't reach here based on grammar
        die "Unexpected number of children in QualifiedIdentifier: " . scalar(@children);
    }
}

1;
