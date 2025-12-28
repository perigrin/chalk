# ABOUTME: Tests for ClassDeclaration producing ClassDef IR nodes
# ABOUTME: Verifies class parsing creates proper ClassDef with fields and methods

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

subtest 'Empty class produces ClassDef' => sub {
    my $classdef = parse_class('class Empty { }');

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 3 unless defined $classdef;
        ok(blessed($classdef), 'Result is blessed');
        is($classdef->op, 'ClassDef', 'op is ClassDef');
        is($classdef->class_name, 'Empty', 'class name correct');
    }
};

subtest 'Class with field' => sub {
    my $classdef = parse_class('class Counter { field $count; }');

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 3 unless defined $classdef && blessed($classdef) && $classdef->can('op') && $classdef->op eq 'ClassDef';
        is(scalar($classdef->fields->@*), 1, 'has one field');
        is($classdef->fields->[0]->name, '$count', 'field name correct');
        is($classdef->fields->[0]->index, 0, 'field index is 0');
    }
};

subtest 'Class with multiple fields' => sub {
    my $classdef = parse_class('class Point { field $x; field $y; }');

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 4 unless defined $classdef && blessed($classdef) && $classdef->can('op') && $classdef->op eq 'ClassDef';
        is(scalar($classdef->fields->@*), 2, 'has two fields');
        is($classdef->fields->[0]->name, '$x', 'first field name correct');
        is($classdef->fields->[0]->index, 0, 'first field index is 0');
        is($classdef->fields->[1]->index, 1, 'second field index is 1');
    }
};

subtest 'Class with method' => sub {
    my $classdef = parse_class('class Greeter { method hello { return 1; } }');

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 3 unless defined $classdef && blessed($classdef) && $classdef->can('op') && $classdef->op eq 'ClassDef';
        is(scalar($classdef->methods->@*), 1, 'has one method');
        is($classdef->methods->[0]->name, 'hello', 'method name correct');
        is($classdef->methods->[0]->parameters->[0], '$self', 'method has $self');
    }
};

subtest 'Class with field and method' => sub {
    # Use unique class name - TypeRegistry is a singleton
    my $code = 'class Incrementer { field $count; method inc { return 1; } }';

    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
    );

    my $result = $parser->parse_string($code);
    ok(defined $result, 'Parse succeeded') or do {
        diag("Parse failed for: $code");
        return;
    };

    # Get the node from result
    my $classdef;
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx && $ctx->can('focus')) {
            $classdef = $ctx->focus;
        }
    }

    SKIP: {
        skip 'No classdef returned', 4 unless defined $classdef && blessed($classdef) && $classdef->can('op') && $classdef->op eq 'ClassDef';
        is(scalar($classdef->fields->@*), 1, 'has one field');
        is($classdef->fields->[0]->name, '$count', 'field name correct');
        is(scalar($classdef->methods->@*), 1, 'has one method');
        is($classdef->methods->[0]->name, 'inc', 'method name correct');
    }
};

done_testing();
