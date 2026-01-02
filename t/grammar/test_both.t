#!/usr/bin/env perl
use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;

# Load grammar BNF
my $bnf_file = "$RealBin/../../grammar/chalk.bnf";
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf = do { local $/; <$fh> };
close $fh;

subtest 'State variable with constant initialization' => sub {
    my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');
    my $source = q{
class Foo {
    sub test() {
        state $x = 42;
        return $x;
    }
}
};

    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($source);

    ok($result, 'Parses state variable with constant');

    my $ir = $result->context->focus;
    my $classes = $ir->class_defs // [];
    my $class = $classes->[0];
    my $methods = $class->methods // [];
    my $method = $methods->[0];

    my $stmts = $method->body_statements;
    is(scalar(@$stmts), 2, 'Has 2 statements (Store, Return)');

    my $store = $stmts->[0];
    is($store->op, 'Store', 'First statement is Store');
    is($store->var, '$x', 'Store variable is $x');
    is($store->value->op, 'Constant', 'Store value is Constant node');
};

subtest 'State variable with parameter reference' => sub {
    my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');
    my $source = q{
class Foo {
    sub test($class) {
        state $x = $class;
        return $x;
    }
}
};

    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($source);

    ok($result, 'Parses state variable with parameter reference');
    return unless $result;

    my $ir = $result->context->focus;
    print "DEBUG: class_defs count: ", scalar(@{$ir->class_defs // []}), "\n";
    my $classes = $ir->class_defs // [];
    ok(scalar(@$classes) > 0, 'Has class definition') or return;
};

done_testing();
