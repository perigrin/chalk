#!/usr/bin/env perl
# ABOUTME: Test IR structure for assignment statements
# ABOUTME: Verifies that assignments return RHS values (SSA semantics)

use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;

sub parse_and_get_ir {
    my ($source) = @_;

    # Load grammar fresh for each parse to avoid state pollution
    my $bnf_file = "$RealBin/../../grammar/chalk.bnf";
    open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
    my $bnf = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');
    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($source);

    return undef unless $result;
    return $result->context->focus;
}

sub get_method_body_statements {
    my ($ir) = @_;

    my $classes = $ir->class_defs // [];
    unless (@$classes) {
        diag("No classes found");
        return undef;
    }

    my $class = $classes->[0];
    my $methods = $class->methods // [];
    unless (@$methods) {
        diag("No methods found");
        return undef;
    }
    diag("Number of methods: " . scalar(@$methods));

    my $method = $methods->[0];
    diag("Method type: " . ref($method));

    # FunctionDef might not have body_statements yet, try body_node
    if ($method->can('body_statements')) {
        diag("Method has body_statements method");
        my $stmts = $method->body_statements;
        diag("body_statements returned: " . (defined($stmts) ? scalar(@$stmts) . " statements" : "undef"));
        return $stmts;
    } elsif ($method->can('body_node')) {
        diag("Method has body_node method");
        my $body = $method->body_node;
        diag("body_node type: " . (ref($body) || 'scalar'));
        if (ref($body) eq 'HASH' && $body->{statements}) {
            return $body->{statements};
        }
    } else {
        diag("Method has neither body_statements nor body_node");
    }

    return undef;
}

subtest 'Simple variable assignment returns RHS value' => sub {
    my $source = q{
class Test1_Simple {
    sub test($param) {
        my $x = $param;
        return $x;
    }
}
};

    my $ir = parse_and_get_ir($source);
    ok($ir, 'Parsed successfully');

    my $stmts = get_method_body_statements($ir);
    ok($stmts, 'Got method body statements');
    is(scalar(@$stmts), 2, 'Has 2 statements (Parm, Return)');

    # In SSA, assignments are expressions returning RHS values
    my $parm = $stmts->[0];
    is($parm->op, 'Parm', 'First statement is Parm (RHS value)');
    is($parm->name, '$param', 'Parm name is $param');
};

subtest 'State variable with constant returns RHS value' => sub {
    my $source = q{
class Test2_Constant {
    sub test($param) {
        state $x = 42;
        return $x;
    }
}
};

    my $ir = parse_and_get_ir($source);
    ok($ir, 'Parsed successfully') or return;

    my $stmts = get_method_body_statements($ir);
    ok($stmts, 'Got method body statements') or return;
    ok(ref($stmts) eq 'ARRAY', 'stmts is array ref') or return;
    is(scalar(@$stmts), 2, 'Has 2 statements (Constant, Return)') or return;

    # In SSA, assignments are expressions returning RHS values
    my $constant = $stmts->[0];
    ok($constant, 'First statement exists') or return;
    is($constant->op, 'Constant', 'First statement is Constant (RHS value)') or return;
    is($constant->value, 42, 'Constant value is 42');
};

subtest 'State variable with parameter returns RHS value' => sub {
    my $source = q{
class Test3_Parameter {
    sub test($param) {
        state $x = $param;
        return $x;
    }
}
};

    my $ir = parse_and_get_ir($source);
    ok($ir, 'Parsed successfully');

    my $stmts = get_method_body_statements($ir);
    ok($stmts, 'Got method body statements');
    is(scalar(@$stmts), 2, 'Has 2 statements (Parm, Return)');

    # In SSA, assignments are expressions returning RHS values
    my $parm = $stmts->[0];
    is($parm->op, 'Parm', 'First statement is Parm (RHS value)');
    is($parm->name, '$param', 'Parm name is $param');
};

subtest 'State variable with method call returns RHS value' => sub {
    my $source = q{
class Test4_MethodCall {
    sub test($class) {
        state $singleton = $class->new();
        return $singleton;
    }
}
};

    my $ir = parse_and_get_ir($source);
    ok($ir, 'Parsed successfully') or do {
        diag("Parse failed");
        return;
    };

    my $stmts = get_method_body_statements($ir);
    ok($stmts, 'Got method body statements') or do {
        diag("No method body statements");
        return;
    };

    is(scalar(@$stmts), 2, 'Has 2 statements (CallEnd, Return)') or return;

    # In SSA, assignments are expressions returning RHS values
    my $call_end = $stmts->[0];
    is($call_end->op, 'CallEnd', 'First statement is CallEnd (RHS value)') or do {
        diag("First statement is not CallEnd, it's: " . $call_end->op);
        return;
    };

    my $call = $call_end->call;
    ok($call, 'CallEnd has call field');
    is($call->op, 'Call', 'Inner node is Call');

    my $receiver = $call->receiver;
    ok($receiver, 'Call has receiver');
    is($receiver->op, 'Parm', 'Receiver is Parm (parameter replacement worked)');
    is($receiver->name, '$class', 'Receiver name is $class');
};

done_testing();
