#!/usr/bin/env perl
# ABOUTME: Test that ClassDef IR nodes correctly capture use overload mappings
# ABOUTME: Verifies Phase 2 (IR Integration) for XS overload support

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Scalar::Util 'blessed';
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;

# Load grammar once for all tests
my $bnf_file = "$RealBin/../../grammar/chalk.bnf";
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'ClassDeclaration', 'Chalk');

sub parse_class {
    my ($code) = @_;

    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
    );

    my $result = $parser->parse_string($code);
    return undef unless $result;

    # Extract the actual node from the parse result
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx && $ctx->can('focus')) {
            return $ctx->focus;
        }
    }

    return $result;
}

subtest 'Class with single use overload' => sub {
    my $classdef = parse_class(q{class Token {
    field $value :param;

    method value() { return $value; }

    use overload '""' => 'value';
}});

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 3 unless defined $classdef;

        is(ref($classdef), 'Chalk::IR::Node::ClassDef', 'Returned ClassDef node');
        is($classdef->class_name, 'Token', 'Class name captured');

        my $mappings = $classdef->overload_mappings;
        ok($mappings, 'ClassDef has overload_mappings');
        is_deeply($mappings, {'""' => 'value'}, 'Overload mapping captured correctly');
    }
};

subtest 'Class with multiple use overload operators' => sub {
    my $classdef = parse_class(q{class Token {
    field $value :param;

    method value() { return $value; }
    method _string_eq($other) { return $value eq $other; }
    method _string_cmp($other) { return $value cmp $other; }

    use overload
        '""'  => 'value',
        'eq'  => '_string_eq',
        'cmp' => '_string_cmp';
}});

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 2 unless defined $classdef;

        my $mappings = $classdef->overload_mappings;
        my $expected = {
            '""'  => 'value',
            'eq'  => '_string_eq',
            'cmp' => '_string_cmp',
        };
        is_deeply($mappings, $expected, 'Multiple overload mappings captured');
    }
};

subtest 'Class with multiple use overload statements (should merge)' => sub {
    my $classdef = parse_class(q{class Token {
    field $value :param;

    method value() { return $value; }
    method equals($other) { return $value eq $other; }

    use overload '""' => 'value';
    use overload 'eq' => 'equals';
}});

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 2 unless defined $classdef;

        my $mappings = $classdef->overload_mappings;
        my $expected = {
            '""' => 'value',
            'eq' => 'equals',
        };
        is_deeply($mappings, $expected, 'Multiple use overload statements merge correctly');
    }
};

done_testing;
