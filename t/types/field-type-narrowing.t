#!/usr/bin/env perl
# ABOUTME: Tests for field initializer type narrowing in TypeInference semiring
# ABOUTME: Validates that field types are narrowed from Any to specific types based on initializers
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
use Chalk::Grammar::Chalk::Rule::Number;
use Chalk::Grammar::Chalk::Rule::String;
use Chalk::Grammar::Chalk::Rule::ReferenceConstructor;
use Chalk::Grammar::Chalk::Rule::Literal;
use Chalk::Semiring::TypeInference;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Create parser with TypeInference semiring to enable type inference
my $semiring = Chalk::Semiring::TypeInference->new();
my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => $semiring
);
my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();

# Test 1: Integer literal field initializer narrows to Int
subtest 'Integer literal field initializer narrows to Int' => sub {
    $registry->reset();

    my $code = q{class Counter { field $count = 0; }};
    my $ast = $parser->parse_string($code);
    ok($ast, 'Class with integer field initializer parses');

    my $counter_type = $registry->lookup('Counter');
    ok($counter_type->is_complete(), 'Counter is complete');
    my $count_type = $counter_type->field_type('$count');

    isa_ok($count_type, 'Chalk::Grammar::Chalk::Type::Int', 'Field $count has type Int');
};

# Test 2: Float literal field initializer narrows to Num
subtest 'Float literal field initializer narrows to Num' => sub {
    $registry->reset();

    my $code = q{class Measurement { field $value = 3.14; }};
    my $ast = $parser->parse_string($code);
    ok($ast, 'Class with float field initializer parses');

    my $measurement_type = $registry->lookup('Measurement');
    my $value_type = $measurement_type->field_type('$value');

    isa_ok($value_type, 'Chalk::Grammar::Chalk::Type::Num', 'Field $value has type Num');
};

# Test 3: String literal field initializer narrows to Str
subtest 'String literal field initializer narrows to Str' => sub {
    $registry->reset();

    my $code = q{class Person { field $name = "unknown"; }};
    my $ast = $parser->parse_string($code);
    ok($ast, 'Class with string field initializer parses');

    my $person_type = $registry->lookup('Person');
    my $name_type = $person_type->field_type('$name');

    isa_ok($name_type, 'Chalk::Grammar::Chalk::Type::Str', 'Field $name has type Str');
};

# Test 4: Array constructor field initializer narrows to ArrayRef
subtest 'Array constructor field initializer narrows to ArrayRef' => sub {
    $registry->reset();

    my $code = q{class Container { field $items = []; }};
    my $ast = $parser->parse_string($code);
    ok($ast, 'Class with array constructor field initializer parses');

    my $container_type = $registry->lookup('Container');
    my $items_type = $container_type->field_type('$items');

    isa_ok($items_type, 'Chalk::Grammar::Chalk::Type::ArrayRef', 'Field $items has type ArrayRef');
};

# Test 5: Hash constructor field initializer narrows to HashRef
subtest 'Hash constructor field initializer narrows to HashRef' => sub {
    $registry->reset();

    my $code = q{class Config { field $options = {}; }};
    my $ast = $parser->parse_string($code);
    ok($ast, 'Class with hash constructor field initializer parses');

    my $config_type = $registry->lookup('Config');
    my $options_type = $config_type->field_type('$options');

    isa_ok($options_type, 'Chalk::Grammar::Chalk::Type::HashRef', 'Field $options has type HashRef');
};

# Test 6: Uninitialized fields remain Any
subtest 'Uninitialized fields remain Any' => sub {
    $registry->reset();

    my $code = q{class Point { field $x; field $y; }};
    my $ast = $parser->parse_string($code);
    ok($ast, 'Class with uninitialized fields parses');

    my $point_type = $registry->lookup('Point');
    my $x_type = $point_type->field_type('$x');
    my $y_type = $point_type->field_type('$y');

    isa_ok($x_type, 'Chalk::Grammar::Chalk::Type::Any', 'Uninitialized field $x remains type Any');
    isa_ok($y_type, 'Chalk::Grammar::Chalk::Type::Any', 'Uninitialized field $y remains type Any');
};

# Test 7: Multiple classes don't interfere
subtest 'Multiple classes with different field types' => sub {
    $registry->reset();

    my $code = q{
        class Counter { field $count = 0; }
        class Person { field $name = "unknown"; }
    };
    my $ast = $parser->parse_string($code);
    ok($ast, 'Multiple classes parse');

    my $counter_type = $registry->lookup('Counter');
    my $person_type = $registry->lookup('Person');

    my $count_type = $counter_type->field_type('$count');
    my $name_type = $person_type->field_type('$name');

    isa_ok($count_type, 'Chalk::Grammar::Chalk::Type::Int', 'Counter.$count has type Int');
    isa_ok($name_type, 'Chalk::Grammar::Chalk::Type::Str', 'Person.$name has type Str');
};

# Test 8: Mixed initialized and uninitialized fields
subtest 'Mixed initialized and uninitialized fields' => sub {
    $registry->reset();

    my $code = q{
        class Mixed {
            field $initialized = 42;
            field $uninitialized;
        }
    };
    my $ast = $parser->parse_string($code);
    ok($ast, 'Class with mixed fields parses');

    my $mixed_type = $registry->lookup('Mixed');
    my $init_type = $mixed_type->field_type('$initialized');
    my $uninit_type = $mixed_type->field_type('$uninitialized');

    isa_ok($init_type, 'Chalk::Grammar::Chalk::Type::Int', 'Initialized field has type Int');
    isa_ok($uninit_type, 'Chalk::Grammar::Chalk::Type::Any', 'Uninitialized field has type Any');
};

done_testing();
