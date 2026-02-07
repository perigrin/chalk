# ABOUTME: Generated BNF meta-grammar from bootstrap compiler.
# ABOUTME: Equivalent to hand-written Chalk::Grammar::BNF.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::BNF::Generated {
    use Chalk::Grammar::Rule;
    use Chalk::Grammar::Symbol;

    sub grammar {
        my @rules;

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Grammar',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*') ,
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Rule', quantifier => '+') ,
            ]],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Rule',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Identifier') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '::=') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*') ,
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Alternatives') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => ';') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*') ,
            ]],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Alternatives',
            expressions => [
            [
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Sequence') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\|') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)*') ,
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Alternatives') ,
            ],
            [
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Sequence') ,
            ],
        ],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Sequence',
            expressions => [
            [
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Element') ,
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:\\s|#[^\\n]*)+') ,
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Sequence') ,
            ],
            [
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Element') ,
            ],
        ],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Element',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Atom') ,
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Quantifier', quantifier => '?') ,
            ]],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Atom',
            expressions => [
            [
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Identifier') ,
            ],
            [
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'InlineRegex') ,
            ],
        ],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Quantifier',
            expressions => [
            [
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\*') ,
            ],
            [
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\+') ,
            ],
            [
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\?') ,
            ],
        ],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Comment',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '#[^\\n]*') ,
            ]],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'Identifier',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '[A-Za-z_][A-Za-z_0-9]*') ,
            ]],
        );

        push @rules, Chalk::Grammar::Rule->new(
            name => 'InlineRegex',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\/(?:[^\\/\\\\]|\\\\.)*\\/') ,
            ]],
        );

        return \@rules;
    }
}
