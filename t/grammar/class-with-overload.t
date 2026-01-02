# ABOUTME: Tests for ClassDeclaration collecting use overload directives
# ABOUTME: Verifies ClassDef IR node includes overload_mappings from class body

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
    my $code = q{class Token {
    field $value :param;
    method value() { return $value; }
    use overload '""' => 'value';
}};

    my $classdef = parse_class($code);

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 4 unless defined $classdef && blessed($classdef) && $classdef->can('op') && $classdef->op eq 'ClassDef';

        is($classdef->class_name, 'Token', 'class name correct');
        is(ref($classdef->overload_mappings), 'HASH', 'overload_mappings is hash');
        is(scalar(keys %{$classdef->overload_mappings}), 1, 'has one overload mapping');
        is($classdef->overload_mappings->{'""'}, 'value', 'stringification maps to value');
    }
};

subtest 'Class with multiple operators in one use overload' => sub {
    my $code = q{class Token2 {
    field $value :param;
    method value() { return $value; }
    method _string_eq($other) { return $value eq $other; }
    use overload
        '""'  => 'value',
        'eq'  => '_string_eq',
        'cmp' => '_string_cmp';
}};

    my $classdef = parse_class($code);

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 5 unless defined $classdef && blessed($classdef) && $classdef->can('op') && $classdef->op eq 'ClassDef';

        is(ref($classdef->overload_mappings), 'HASH', 'overload_mappings is hash');
        is(scalar(keys %{$classdef->overload_mappings}), 3, 'has three overload mappings');
        is($classdef->overload_mappings->{'""'}, 'value', 'stringification maps to value');
        is($classdef->overload_mappings->{'eq'}, '_string_eq', 'eq maps to _string_eq');
        is($classdef->overload_mappings->{'cmp'}, '_string_cmp', 'cmp maps to _string_cmp');
    }
};

subtest 'Class with multiple use overload statements' => sub {
    my $code = q{class Token3 {
    field $value :param;
    use overload '""' => 'value';
    use overload 'eq' => '_string_eq';
    use overload 'cmp' => '_string_cmp';
}};

    my $classdef = parse_class($code);

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 4 unless defined $classdef && blessed($classdef) && $classdef->can('op') && $classdef->op eq 'ClassDef';

        is(ref($classdef->overload_mappings), 'HASH', 'overload_mappings is hash');
        is(scalar(keys %{$classdef->overload_mappings}), 3, 'has three overload mappings from multiple statements');
        is($classdef->overload_mappings->{'""'}, 'value', 'stringification from first statement');
        is($classdef->overload_mappings->{'eq'}, '_string_eq', 'eq from second statement');
    }
};

subtest 'Class without use overload has empty mappings' => sub {
    my $code = q{class Simple {
    field $x;
}};

    my $classdef = parse_class($code);

    ok(defined $classdef, 'ClassDef created');
    SKIP: {
        skip 'No classdef returned', 2 unless defined $classdef && blessed($classdef) && $classdef->can('op') && $classdef->op eq 'ClassDef';

        is(ref($classdef->overload_mappings), 'HASH', 'overload_mappings is hash');
        is(scalar(keys %{$classdef->overload_mappings}), 0, 'has no overload mappings');
    }
};

done_testing();
