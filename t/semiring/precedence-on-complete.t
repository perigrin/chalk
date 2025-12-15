#!/usr/bin/env perl
# ABOUTME: Test Precedence semiring's on_complete() method extracts operator information
# ABOUTME: Verifies operator is attached to PrecedenceElement during parsing, not post-hoc
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Composite;

# Load Chalk grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Perl precedence table
my @precedence_table = (
    { assoc => 'left',  ops => ['*', '/', '%'] },  # Index 0 - Higher precedence
    { assoc => 'left',  ops => ['+', '-'] },       # Index 1 - Lower precedence
);

# NOTE: These tests verify aspirational behavior for operator extraction during on_complete().
# Currently, the Precedence semiring doesn't extract operator information from completed
# ArithmeticOp rules - this is a known limitation. When this feature is implemented,
# these TODO blocks should be removed.

subtest 'on_complete() extracts operator for single ArithmeticOp' => sub {
    todo 'Operator extraction during on_complete() not yet implemented' => sub {
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table,
        shared_context => { forest => $sppf_sr->forest }
    );

    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $prec_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr
    );

    # Simple expression with just one operator
    my $result = $parser->parse_string('return 1 + 2;');
    ok $result, 'Simple addition parses';

    SKIP: {
        skip 'Parse failed' unless $result;

        my @elements = $result->elements->@*;
        my $prec_element = $elements[1];  # Precedence element

        ok $prec_element, 'Has precedence element';
        isa_ok $prec_element, ['Chalk::Semiring::PrecedenceElement'];

        # The key test: operator should be extracted during on_complete()
        ok defined($prec_element->operator),
            'Precedence element has operator defined';
        is $prec_element->operator, '+',
            'Operator is correctly identified as "+"';
        is $prec_element->precedence_level, 1,
            'Operator has correct precedence level (1 for +)';
        is $prec_element->associativity, 'left',
            'Operator has correct associativity (left)';
    }
    };  # end todo
};

subtest 'on_complete() extracts operators for nested ArithmeticOp' => sub {
    todo 'Precedence parsing for complex expressions not yet implemented' => sub {
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table,
        shared_context => { forest => $sppf_sr->forest }
    );

    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $prec_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr
    );

    # Track on_complete calls
    my @on_complete_calls;
    {
        no warnings 'redefine';
        my $orig_on_complete = \&Chalk::Semiring::Precedence::on_complete;
        local *Chalk::Semiring::Precedence::on_complete = sub {
            my ($self, $item, $element) = @_;
            my $result = $orig_on_complete->($self, $item, $element);

            # Track if this completion was for ArithmeticOp
            my $rule = $item->rule;
            if ($rule && $rule->lhs eq 'ArithmeticOp') {
                push @on_complete_calls, {
                    span => [$item->start_pos, $item->end_pos],
                    has_operator => defined($result->operator),
                    operator => $result->operator // 'undef',
                    valid => $result->valid,
                };
            }
            return $result;
        };

        my $result = $parser->parse_string('return 1 + 2 * 3;');
        ok $result, 'Expression with precedence parses';
    }

    # Should have on_complete calls for each ArithmeticOp that completed
    ok scalar(@on_complete_calls) > 0,
        'on_complete was called for ArithmeticOp rules';

    note("on_complete calls for ArithmeticOp:");
    for my $call (@on_complete_calls) {
        my $span = sprintf("[%d,%d]", $call->{span}[0], $call->{span}[1]);
        note("  ArithmeticOp$span: operator=" . $call->{operator} .
             " valid=" . $call->{valid});
    }

    # At least some completions should have operator extracted
    my @with_ops = grep { $_->{has_operator} } @on_complete_calls;
    ok scalar(@with_ops) > 0,
        'At least some on_complete calls extracted operator';

    # Should see both + and * operators
    my @plus_ops = grep { $_->{operator} eq '+' } @on_complete_calls;
    my @mult_ops = grep { $_->{operator} eq '*' } @on_complete_calls;

    ok scalar(@plus_ops) > 0, 'Found ArithmeticOp with + operator';
    ok scalar(@mult_ops) > 0, 'Found ArithmeticOp with * operator';

    # CRITICAL TEST: Should see BOTH operators at the root span [0,16]
    my @root_completions = grep {
        $_->{span}[0] == 0 && $_->{span}[1] == 16
    } @on_complete_calls;

    note("Root ArithmeticOp[0,16] completions: " . scalar(@root_completions));
    for my $comp (@root_completions) {
        note("  operator=" . $comp->{operator});
    }

    # This is the key test that should FAIL
    todo 'Parser should generate both parse alternatives at root span' => sub {
        cmp_ok scalar(@root_completions), '>=', 2,
            'Should have at least 2 on_complete calls at root span [0,16]';

        my @root_plus = grep { $_->{operator} eq '+' } @root_completions;
        my @root_mult = grep { $_->{operator} eq '*' } @root_completions;

        ok scalar(@root_plus) > 0,
            'Root span should have completion with + operator';
        ok scalar(@root_mult) > 0,
            'Root span should have completion with * operator';
    };
    };  # end outer todo
};

subtest 'on_complete() enables multiply() to validate precedence' => sub {
    todo 'Precedence parsing for complex expressions not yet implemented' => sub {
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table,
        shared_context => { forest => $sppf_sr->forest }
    );

    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $prec_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr
    );

    # Track multiply() calls to see if they have operator info
    my @multiply_calls;
    {
        no warnings 'redefine';
        my $orig_multiply = \&Chalk::Semiring::PrecedenceElement::multiply;
        local *Chalk::Semiring::PrecedenceElement::multiply = sub {
            my ($self, $other, $swap) = @_;

            push @multiply_calls, {
                self_op => $self->operator // 'undef',
                other_op => $other->operator // 'undef',
            };

            return $orig_multiply->($self, $other, $swap);
        };

        my $result = $parser->parse_string('return 1 + 2 * 3;');
        ok $result, 'Expression parses';
    }

    note("multiply() calls:");
    for my $call (@multiply_calls) {
        note("  self: " . $call->{self_op} . ", other: " . $call->{other_op});
    }

    # At least some multiply() calls should have operator info
    my @with_ops = grep {
        $_->{self_op} ne 'undef' || $_->{other_op} ne 'undef'
    } @multiply_calls;

    ok scalar(@with_ops) > 0,
        'At least some multiply() calls have operator information available';
    };  # end todo
};
