# ABOUTME: Tests for MethodDeclaration semantic action
# ABOUTME: Verifies method produces FunctionDef with implicit $self parameter

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
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'MethodDeclaration', 'Chalk');

sub parse_method {
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

subtest 'MethodDeclaration rule exists in grammar' => sub {
    ok(defined($grammar), 'Grammar loaded');
    my $start = $grammar->start_symbol;
    is($start, 'MethodDeclaration', 'Start symbol is MethodDeclaration');
};

subtest 'Method without parameters' => sub {
    my $func = parse_method('method foo { return 1; }');

    ok(defined $func, 'FunctionDef created');
    ok(blessed($func), 'Result is blessed');
    is($func->op, 'FunctionDef', 'op is FunctionDef');
    is($func->name, 'foo', 'method name correct');
    is($func->parameters->[0], '$self', 'first param is $self');
    is(scalar(@{$func->parameters}), 1, 'only $self parameter');
};

subtest 'Method with single parameter' => sub {
    my $func = parse_method('method add($x) { return $x; }');

    ok(defined $func, 'FunctionDef created');
    is($func->name, 'add', 'method name correct');
    is_deeply($func->parameters, ['$self', '$x'], 'params include $self first');
};

subtest 'Method with multiple parameters' => sub {
    my $func = parse_method('method compute($a, $b, $c) { return 0; }');

    ok(defined $func, 'FunctionDef created');
    is($func->name, 'compute', 'method name correct');
    is_deeply($func->parameters, ['$self', '$a', '$b', '$c'],
        'params include $self followed by declared params');
};

done_testing();
