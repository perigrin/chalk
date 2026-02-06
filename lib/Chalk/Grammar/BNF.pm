# ABOUTME: BNF meta-grammar data structure for bootstrapping Chalk compiler.
# ABOUTME: Provides 10-rule meta-grammar as Chalk::Grammar::Rule objects.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Grammar::BNF {
    use Chalk::Grammar::Rule;
    use Chalk::Grammar::Symbol;

    sub grammar {
        my @rules;

        # Grammar ::= /(?:\s|#[^\n]*)*/ Rule+
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Grammar',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*'),
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Rule', quantifier => '+'),
            ]],
        );

        # Rule ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Rule',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Identifier'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '::='),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*'),
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Alternatives'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => ';'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*'),
            ]],
        );

        # Alternatives ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Alternatives',
            expressions => [
                [
                    Chalk::Grammar::Symbol->new(type => 'reference', value => 'Sequence'),
                    Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*'),
                    Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\|'),
                    Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*'),
                    Chalk::Grammar::Symbol->new(type => 'reference', value => 'Alternatives'),
                ],
                [
                    Chalk::Grammar::Symbol->new(type => 'reference', value => 'Sequence'),
                ],
            ],
        );

        # Sequence ::= Sequence_Element /(?:\s|#[^\n]*)+/ Sequence | Sequence_Element
        # Note: Sequence_Element references the Element rule
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Sequence',
            expressions => [
                [
                    Chalk::Grammar::Symbol->new(type => 'reference', value => 'Element'),
                    Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)+'),
                    Chalk::Grammar::Symbol->new(type => 'reference', value => 'Sequence'),
                ],
                [
                    Chalk::Grammar::Symbol->new(type => 'reference', value => 'Element'),
                ],
            ],
        );

        # Element ::= Atom Quantifier?
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Element',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Atom'),
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Quantifier', quantifier => '?'),
            ]],
        );

        # Atom ::= Identifier | InlineRegex
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Atom',
            expressions => [
                [
                    Chalk::Grammar::Symbol->new(type => 'reference', value => 'Identifier'),
                ],
                [
                    Chalk::Grammar::Symbol->new(type => 'reference', value => 'InlineRegex'),
                ],
            ],
        );

        # Quantifier ::= /\*/ | /\+/ | /\?/
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Quantifier',
            expressions => [
                [
                    Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\*'),
                ],
                [
                    Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\+'),
                ],
                [
                    Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\?'),
                ],
            ],
        );

        # Comment ::= /#[^\n]*/
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Comment',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '#[^\\n]*'),
            ]],
        );

        # Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/
        push @rules, Chalk::Grammar::Rule->new(
            name => 'Identifier',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '[A-Za-z_][A-Za-z_0-9]*'),
            ]],
        );

        # InlineRegex ::= /\/(?:[^\/\\]|\\.)*\//
        push @rules, Chalk::Grammar::Rule->new(
            name => 'InlineRegex',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\/(?:[^\\/\\\\]|\\\\.)*\\/'),
            ]],
        );

        return \@rules;
    }
}
