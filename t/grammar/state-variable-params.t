#!/usr/bin/env perl
# ABOUTME: Test state variables with parameter references (#559)
# ABOUTME: Ensures UnboundVariable→Parm replacement works inside Store nodes

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
class Test1_Constant {
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
    is(scalar(@$stmts), 2, 'Has 2 statements (Constant, Return)');

    # In SSA, assignments return their RHS value, not Store statements
    my $constant = $stmts->[0];
    is($constant->op, 'Constant', 'First statement is Constant (assignment RHS)');
    is($constant->value, 42, 'Constant value is 42');
};

subtest 'State variable with parameter reference' => sub {
    my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');
    my $source = q{
class Test2_Parameter {
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
    my $classes = $ir->class_defs // [];
    ok(scalar(@$classes) > 0, 'Has class definition') or return;

    my $class = $classes->[0];
    ok($class, 'Got class object') or return;

    my $methods = $class->methods // [];
    ok(scalar(@$methods) > 0, 'Has methods') or return;

    my $method = $methods->[0];

    my $stmts = $method->body_statements;
    is(scalar(@$stmts), 2, 'Has 2 statements (Parm, Return)');

    # In SSA, assignments return their RHS value
    # THIS IS THE KEY TEST - should be Parm, not UnboundVariable
    my $parm = $stmts->[0];
    is($parm->op, 'Parm', 'First statement is Parm (assignment RHS, not UnboundVariable)');
    is($parm->name, '$class', 'Parm name is $class');
};

subtest 'State variable with method call on parameter (Type::String BOTTOM case)' => sub {
    my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');
    my $source = q{
class Test3_MethodCall {
    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }
}
};

    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($source);

    ok($result, 'Parses state variable with method call on parameter');
    return unless $result;

    my $ir = $result->context->focus;
    my $classes = $ir->class_defs // [];
    ok(scalar(@$classes) > 0, 'Has class definition') or return;

    my $class = $classes->[0];
    ok($class, 'Got class object') or return;

    my $methods = $class->methods // [];
    ok(scalar(@$methods) > 0, 'Has methods') or return;

    my $method = $methods->[0];

    my $stmts = $method->body_statements;
    is(scalar(@$stmts), 2, 'Has 2 statements (CallEnd, Return)');

    # In SSA, assignments are expressions that return values, not Store statements
    # The first statement is the CallEnd from the assignment expression
    my $call_end = $stmts->[0];
    is($call_end->op, 'CallEnd', 'First statement is CallEnd');

    my $call = $call_end->call;
    ok($call, 'CallEnd has call field');
    is($call->op, 'Call', 'Inner node is Call');

    # The receiver of the method call should be a Parm node, not UnboundVariable
    # This verifies that parameter replacement worked correctly
    my $receiver = $call->receiver;
    ok($receiver, 'Call has receiver');
    is($receiver->op, 'Parm', 'Receiver is Parm node (not UnboundVariable)');
    is($receiver->name, '$class', 'Parm name is $class');
};

done_testing();
