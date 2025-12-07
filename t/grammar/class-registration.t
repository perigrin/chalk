#!/usr/bin/env perl
# ABOUTME: Tests for ClassDeclaration parser integration with TypeRegistry
# ABOUTME: Validates field extraction and type inference for class registration
use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use File::Spec;

use lib "$RealBin/../../lib";
use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk::TypeRegistry;
use Chalk::Grammar::Chalk::Rule::ClassDeclaration;
use Chalk::Grammar::Chalk::Rule::QualifiedIdentifier;
use Chalk::Grammar::Chalk::Rule::Identifier;
use Chalk::Grammar::Chalk::Rule::Block;
use Chalk::Grammar::Chalk::Rule::StatementList;
use Chalk::Grammar::Chalk::Rule::Statement;
use Chalk::Grammar::Chalk::Rule::Assignment;
use Chalk::Grammar::Chalk::Rule::VariableDeclaration;
use Chalk::Grammar::Chalk::Rule::Variable;
use Chalk::Grammar::Chalk::Rule::ScalarVar;
use Chalk::Grammar::Chalk::Rule::LexicalDeclarator;
use Chalk::Grammar::Chalk::Rule::ExpressionList;
use Chalk::Grammar::Chalk::Rule::Expression;
use Chalk::Semiring::Semantic;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Create parser with Semantic semiring to enable semantic actions
my $semiring = Chalk::Semiring::Semantic->new(
    env => {},
    grammar => $chalk_grammar
);
my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => $semiring
);
my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();

# Test 1: Simple class with fields registers in TypeRegistry
subtest 'Simple class with fields registers in TypeRegistry' => sub {
    $registry->reset();

    my $code = q{class Point { field $x; field $y; }};
    my $ast = $parser->parse_string($code);
    ok($ast, 'Simple class parses');

    # Verify class was registered
    ok($registry->has_class('Point'), 'Point class registered in TypeRegistry');

    my $point_type = $registry->lookup('Point');
    ok($point_type->is_complete(), 'Point class is complete (not a placeholder)');

    # Verify fields were extracted
    ok($point_type->has_field('$x'), 'Point has field $x');
    ok($point_type->has_field('$y'), 'Point has field $y');
};

# Test 2: Field names extracted correctly (with and without initializers)
subtest 'Field names extracted correctly' => sub {
    $registry->reset();

    my $code = q{
        class Counter {
            field $count = 0;
            field $name;
            field $max = 100;
        }
    };
    my $ast = $parser->parse_string($code);
    ok($ast, 'Class with mixed fields parses');

    my $counter_type = $registry->lookup('Counter');
    ok($counter_type->is_complete(), 'Counter is complete');

    # All three fields should be present
    ok($counter_type->has_field('$count'), 'Counter has field $count');
    ok($counter_type->has_field('$name'), 'Counter has field $name');
    ok($counter_type->has_field('$max'), 'Counter has field $max');
};

# Test 3: Self-referential class (Node with $left/$right fields)
subtest 'Self-referential class with recursive fields' => sub {
    $registry->reset();

    my $code = q{
        class Node {
            field $value;
            field $left;
            field $right;
        }
    };
    my $ast = $parser->parse_string($code);
    ok($ast, 'Self-referential class parses');

    my $node_type = $registry->lookup('Node');
    ok($node_type->is_complete(), 'Node is complete');

    # All fields present
    ok($node_type->has_field('$value'), 'Node has field $value');
    ok($node_type->has_field('$left'), 'Node has field $left');
    ok($node_type->has_field('$right'), 'Node has field $right');
};

# Test 4: Mutually recursive classes
subtest 'Mutually recursive classes' => sub {
    $registry->reset();

    my $code = q{
        class A { field $b_ref; }
        class B { field $a_ref; }
    };
    my $ast = $parser->parse_string($code);
    ok($ast, 'Mutually recursive classes parse');

    # Both classes should be registered
    ok($registry->has_class('A'), 'Class A registered');
    ok($registry->has_class('B'), 'Class B registered');

    my $a_type = $registry->lookup('A');
    my $b_type = $registry->lookup('B');

    ok($a_type->is_complete(), 'A is complete');
    ok($b_type->is_complete(), 'B is complete');

    ok($a_type->has_field('$b_ref'), 'A has field $b_ref');
    ok($b_type->has_field('$a_ref'), 'B has field $a_ref');
};

# Test 5: Field types default to Any
subtest 'Field types default to Any' => sub {
    $registry->reset();

    my $code = q{class Simple { field $x; }};
    my $ast = $parser->parse_string($code);
    ok($ast, 'Simple class parses');

    my $simple_type = $registry->lookup('Simple');
    my $x_type = $simple_type->field_type('$x');

    isa_ok($x_type, 'Chalk::Grammar::Chalk::Type::Any', 'Field type defaults to Any');
};

done_testing();
