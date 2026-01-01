#!/usr/bin/env perl
# ABOUTME: Tests for SingleQuotedString semantic action with escape handling
# ABOUTME: Verifies correct processing of \\ and \' escapes in single-quoted strings

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Grammar::Chalk::Rule::SingleQuotedString;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

subtest 'Simple single-quoted string without escapes' => sub {
    # Context for 'hello'
    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => q{'hello'},
                children => [],
                start_pos => 0,
                end_pos => 7,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 7,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::SingleQuotedString->new(
        lhs => 'SingleQuotedString',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result) && $result->isa('Chalk::IR::Node::Constant'),
       'Returns Constant node');
    is($result->value, 'hello', 'String value is correct');
    ok($result->type->isa('Chalk::Grammar::Chalk::Type::Str'),
       'Type is Str');
};

subtest 'Single-quoted string with escaped quote' => sub {
    # Context for 'it\'s'
    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => q{'it\'s'},
                children => [],
                start_pos => 0,
                end_pos => 7,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 7,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::SingleQuotedString->new(
        lhs => 'SingleQuotedString',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result) && $result->isa('Chalk::IR::Node::Constant'),
       'Returns Constant node');
    is($result->value, q{it's}, 'Escaped quote processed correctly');
    ok($result->type->isa('Chalk::Grammar::Chalk::Type::Str'),
       'Type is Str');
};

subtest 'Single-quoted string with escaped backslash' => sub {
    # Context for 'back\\slash'
    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => q{'back\\slash'},
                children => [],
                start_pos => 0,
                end_pos => 13,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 13,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::SingleQuotedString->new(
        lhs => 'SingleQuotedString',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result) && $result->isa('Chalk::IR::Node::Constant'),
       'Returns Constant node');
    is($result->value, q{back\slash}, 'Escaped backslash processed correctly');
    ok($result->type->isa('Chalk::Grammar::Chalk::Type::Str'),
       'Type is Str');
};

subtest 'Single-quoted string with literal backslash sequences' => sub {
    # Context for 'literal \n stays' - \n should stay as literal \n
    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => q{'literal \n stays'},
                children => [],
                start_pos => 0,
                end_pos => 18,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 18,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::SingleQuotedString->new(
        lhs => 'SingleQuotedString',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result) && $result->isa('Chalk::IR::Node::Constant'),
       'Returns Constant node');
    is($result->value, q{literal \n stays},
       'Non-escaped backslash sequences stay literal');
    ok($result->type->isa('Chalk::Grammar::Chalk::Type::Str'),
       'Type is Str');
};

subtest 'Empty single-quoted string' => sub {
    # Context for ''
    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => q{''},
                children => [],
                start_pos => 0,
                end_pos => 2,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 2,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::SingleQuotedString->new(
        lhs => 'SingleQuotedString',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result) && $result->isa('Chalk::IR::Node::Constant'),
       'Returns Constant node');
    is($result->value, '', 'Empty string value is correct');
    ok($result->type->isa('Chalk::Grammar::Chalk::Type::Str'),
       'Type is Str');
};

subtest 'Single-quoted string with multiple escapes' => sub {
    # Context for 'can\'t use \\ here'
    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => q{'can\'t use \\ here'},
                children => [],
                start_pos => 0,
                end_pos => 20,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 20,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::SingleQuotedString->new(
        lhs => 'SingleQuotedString',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result) && $result->isa('Chalk::IR::Node::Constant'),
       'Returns Constant node');
    is($result->value, q{can't use \ here},
       'Multiple escapes processed correctly');
    ok($result->type->isa('Chalk::Grammar::Chalk::Type::Str'),
       'Type is Str');
};

done_testing();
