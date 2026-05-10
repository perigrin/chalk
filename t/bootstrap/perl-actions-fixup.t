# ABOUTME: Tests _fixup_stmts() ambiguity resolution in Perl::Actions.
# ABOUTME: Validates return/die merging and UseDecl import arg merging across hash seeds.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::IR::UseInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::Program;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build Perl grammar pipeline: IR -> generated Perl -> eval -> grammar objects
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::FixupTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::FixupTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse a source string and extract Perl IR ===

my sub parse_source($source) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result;
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# === Helper to get the flat statement list from a Program IR ===
# Chalk::IR::Program stores statements partitioned; use_decls go into use_decls(),
# classes into classes(), subs into top_level_subs(), bare nodes into other_stmts().
# This helper assembles the full flat list for test assertions.

my sub get_all_stmts($ir) {
    return $ir->inputs()->[0] unless $ir isa Chalk::IR::Program;
    return [
        $ir->use_decls()->@*,
        $ir->classes()->@*,
        $ir->top_level_subs()->@*,
        $ir->other_stmts()->@*,
    ];
}

# === Helper to find a class declaration in IR statements ===

my sub find_class_in_stmts($ir, $class) {
    my @stmts = $ir isa Chalk::IR::Program
        ? $ir->classes()->@*
        : $ir->inputs()->[0]->@*;
    for my $stmt (@stmts) {
        # ClassInfo (new path)
        if ($stmt isa Chalk::IR::ClassInfo) {
            return $stmt;
        }
        # Constructor:ClassDecl (legacy path)
        if ($stmt isa Chalk::IR::Node::Constructor
                && $stmt->class() eq $class) {
            return $stmt;
        }
    }
    return undef;
}

my sub _class_body($class_decl) {
    return $class_decl isa Chalk::IR::ClassInfo
        ? $class_decl->body()
        : $class_decl->inputs()->[2];
}

my sub find_method_in_class($class_decl, $name) {
    my $body = _class_body($class_decl);
    for my $item ($body->@*) {
        if ($item isa Chalk::IR::MethodInfo
                && $item->name() eq $name) {
            return $item;
        }
        if ($item isa Chalk::IR::Node::Constructor
                && $item->class() eq 'MethodDecl'
                && $item->inputs()->[0]->value() eq $name) {
            return $item;
        }
    }
    return undef;
}

# Helper to get method body from either MethodInfo or Constructor:MethodDecl
my sub method_body($method) {
    return $method->body() if $method isa Chalk::IR::MethodInfo;
    return $method->inputs()->[2];
}

# Helper to get method name from either MethodInfo or Constructor:MethodDecl
my sub method_name($method) {
    return $method->name() if $method isa Chalk::IR::MethodInfo;
    return $method->inputs()->[0]->value();
}

# ============================================================
# 1. return + value merging
# ============================================================

{
    my $source = qq{use 5.42.0;\nuse utf8;\nuse experimental 'class';\nclass Foo {\n    method bar() {\n        return 'baz';\n    }\n}\n};
    my $ir = parse_source($source);
    ok(defined $ir, 'return merge: parses');

    SKIP: {
        skip 'return merge: no IR', 4 unless defined $ir;

        my $class_decl = find_class_in_stmts($ir, 'ClassDecl');
        ok(defined $class_decl, 'return merge: found ClassDecl');

        my $method = find_method_in_class($class_decl, 'bar');
        ok(defined $method, 'return merge: found method bar');

        my $body = method_body($method);
        is(scalar $body->@*, 1, 'return merge: method body has 1 item');
        ok($body->[0] isa Chalk::IR::Node::Return, 'return merge: body item is Return CFG node');
    }
}

# ============================================================
# 2. die + message merging
# ============================================================

{
    my $source = qq{use 5.42.0;\nuse utf8;\nuse experimental 'class';\nclass Foo {\n    method bar() {\n        die 'something went wrong';\n    }\n}\n};
    my $ir = parse_source($source);
    ok(defined $ir, 'die merge: parses');

    SKIP: {
        skip 'die merge: no IR', 5 unless defined $ir;

        my $class_decl = find_class_in_stmts($ir, 'ClassDecl');
        ok(defined $class_decl, 'die merge: found ClassDecl');

        my $method = find_method_in_class($class_decl, 'bar');
        ok(defined $method, 'die merge: found method bar');

        my $body = method_body($method);
        is(scalar $body->@*, 1, 'die merge: method body has 1 item');
        isa_ok($body->[0], 'Chalk::IR::Node::Unwind', 'die merge: body item is Unwind CFG node');

        my $args = $body->[0]->inputs()->[1];
        is($args->[0]->value(), 'something went wrong', 'die merge: message preserved');
    }
}

# ============================================================
# 3. UseDecl + split import arg merging
# ============================================================

{
    my $source = qq{use 5.42.0;\nuse utf8;\nuse experimental 'class';\nclass Foo {\n    method bar() {\n        return 'ok';\n    }\n}\n};
    my $ir = parse_source($source);
    ok(defined $ir, 'use merge: parses');

    SKIP: {
        skip 'use merge: no IR', 4 unless defined $ir;

        my $stmts = get_all_stmts($ir);
        # Find the 'experimental' UseInfo
        my $exp_use;
        for my $stmt ($stmts->@*) {
            if ($stmt isa Chalk::IR::UseInfo
                    && $stmt->name() eq 'experimental') {
                $exp_use = $stmt;
                last;
            }
        }
        ok(defined $exp_use, 'use merge: found experimental UseInfo');
        my $import_args = $exp_use->args();
        ok(defined $import_args, 'use merge: args defined');
        is(ref($import_args), 'ARRAY', 'use merge: args is arrayref');
        is($import_args->[0]->value(), 'class', 'use merge: import arg is class');
    }
}

# ============================================================
# 4. return as only method body (no trailing value)
#    In Tier A, return always has a value, but verify structure
# ============================================================

{
    my $source = qq{use 5.42.0;\nuse utf8;\nuse experimental 'class';\nclass Foo {\n    method op() {\n        return 'Start';\n    }\n    method name() {\n        return 'test';\n    }\n}\n};
    my $ir = parse_source($source);
    ok(defined $ir, 'two methods: parses');

    SKIP: {
        skip 'two methods: no IR', 4 unless defined $ir;

        my $class_decl = find_class_in_stmts($ir, 'ClassDecl');
        ok(defined $class_decl, 'two methods: found ClassDecl');

        my $body = _class_body($class_decl);
        is(scalar $body->@*, 2, 'two methods: class body has 2 methods');

        my $m1 = find_method_in_class($class_decl, 'op');
        ok(defined $m1, 'two methods: found method op');
        my $m2 = find_method_in_class($class_decl, 'name');
        ok(defined $m2, 'two methods: found method name');
    }
}

# ============================================================
# 5. Hash-seed stability: parse same snippet with multiple seeds
#    and verify IR structure is identical
# ============================================================

{
    my $source = qq{use 5.42.0;\nuse utf8;\nuse experimental 'class';\nclass Foo :isa(Bar) {\n    method go(\$x) {\n        die 'not implemented';\n    }\n}\n};

    my @seeds = (0, 1, 42, 12345, 99999);
    my @results;

    for my $seed (@seeds) {
        local $ENV{PERL_HASH_SEED} = $seed;
        local $ENV{PERL_PERTURB_KEYS} = 'NO';
        my $ir = parse_source($source);
        if (defined $ir) {
            my $class_decl = find_class_in_stmts($ir, 'ClassDecl');
            my $method = find_method_in_class($class_decl, 'go');
            my $mbody = method_body($method);
            my $cname = $class_decl isa Chalk::IR::ClassInfo
                ? $class_decl->name()
                : $class_decl->inputs()->[0]->value();
            my $cparent = $class_decl isa Chalk::IR::ClassInfo
                ? $class_decl->parent()
                : (defined $class_decl->inputs()->[1] ? $class_decl->inputs()->[1]->value() : undef);
            push @results, {
                seed        => $seed,
                class_name  => $cname,
                parent      => $cparent,
                method_name => method_name($method),
                body_class  => ref($mbody->[0]),
                die_msg     => $mbody->[0]->inputs()->[1][0]->value(),
            };
        } else {
            push @results, { seed => $seed, error => 'no IR' };
        }
    }

    # Verify all seeds produce the same structure
    my $first = $results[0];
    ok(!exists $first->{error}, 'hash-seed stability: seed 0 parses');

    for my $i (1 .. $#results) {
        my $r = $results[$i];
        if (exists $r->{error}) {
            fail("hash-seed stability: seed $r->{seed} failed to parse");
            next;
        }
        is($r->{class_name}, $first->{class_name},
            "hash-seed stability: seed $r->{seed} class name matches");
        is($r->{parent}, $first->{parent},
            "hash-seed stability: seed $r->{seed} parent matches");
        is($r->{method_name}, $first->{method_name},
            "hash-seed stability: seed $r->{seed} method name matches");
        is($r->{body_class}, $first->{body_class},
            "hash-seed stability: seed $r->{seed} body class matches");
        is($r->{die_msg}, $first->{die_msg},
            "hash-seed stability: seed $r->{seed} die message matches");
    }
}

# ============================================================
# 6. push @arr, $x; produces single BuiltinCall with 2 args
#    NOT fragmented [BuiltinCall(push, [@arr]), Constant($x)]
# ============================================================

{
    my $source = qq{push \@arr, \$x;\n};
    my $ir = parse_source($source);
    ok(defined $ir, 'push multi-arg: parses');

    SKIP: {
        skip 'push multi-arg: no IR', 3 unless defined $ir;

        my $stmts = get_all_stmts($ir);
        is(scalar $stmts->@*, 1, 'push multi-arg: one statement (not fragmented)');

        my $call = $stmts->[0];
        is($call->class(), 'BuiltinCall', 'push multi-arg: statement is BuiltinCall');

        my $args = $call->inputs()->[1];
        is(scalar $args->@*, 2, 'push multi-arg: BuiltinCall has 2 args');
    }
}

# === PostfixDeref base expression capture ===
# PostfixDeref grammar: Expression _ /->/ _ /@\*/
# The base Expression must be captured as the target of PostfixDerefExpr.

{
    subtest 'PostfixDeref captures base expression' => sub {
        my $ir = parse_source('$ops->@*;');
        ok(defined $ir, 'PostfixDeref: parses');

        my $stmts = get_all_stmts($ir);
        is(scalar $stmts->@*, 1, 'PostfixDeref: one statement');

        my $deref = $stmts->[0];
        is($deref->class(), 'PostfixDerefExpr', 'PostfixDeref: class');

        my $target = $deref->inputs()->[0];
        ok(defined $target, 'PostfixDeref: target is defined');
        is($target->value(), '$ops', 'PostfixDeref: target is $ops');
        is($deref->inputs()->[1]->value(), '@', 'PostfixDeref: sigil is @');
    };
}

{
    subtest 'PostfixDeref with method chain base' => sub {
        my $ir = parse_source('$self->ops()->@*;');
        ok(defined $ir, 'PostfixDeref chain: parses');

        my $stmts = get_all_stmts($ir);
        is(scalar $stmts->@*, 1, 'PostfixDeref chain: one statement');

        my $deref = $stmts->[0];
        is($deref->class(), 'PostfixDerefExpr', 'PostfixDeref chain: class');

        my $target = $deref->inputs()->[0];
        ok(defined $target, 'PostfixDeref chain: target is defined');
        is($target->class(), 'MethodCallExpr', 'PostfixDeref chain: target is MethodCallExpr');
    };
}

# === MethodCall base expression capture ===
# MethodCall grammar: Expression _ /->/ _ QualifiedIdentifier ...
# The base Expression must be captured as the invocant of MethodCallExpr.

{
    subtest 'MethodCall captures invocant' => sub {
        my $ir = parse_source('$x->foo();');
        ok(defined $ir, 'MethodCall: parses');

        my $stmts = get_all_stmts($ir);
        is(scalar $stmts->@*, 1, 'MethodCall: one statement');

        my $call = $stmts->[0];
        is($call->class(), 'MethodCallExpr', 'MethodCall: class');

        my $invocant = $call->inputs()->[0];
        ok(defined $invocant, 'MethodCall: invocant is defined');
        is($invocant->value(), '$x', 'MethodCall: invocant is $x');
        is($call->inputs()->[1]->value(), 'foo', 'MethodCall: method name');
    };
}

{
    subtest 'MethodCall chain captures invocant' => sub {
        my $ir = parse_source('$x->foo()->bar();');
        ok(defined $ir, 'MethodCall chain: parses');

        my $stmts = get_all_stmts($ir);
        is(scalar $stmts->@*, 1, 'MethodCall chain: one statement');

        my $call = $stmts->[0];
        is($call->class(), 'MethodCallExpr', 'MethodCall chain: class is outer');
        is($call->inputs()->[1]->value(), 'bar', 'MethodCall chain: outer method is bar');

        my $invocant = $call->inputs()->[0];
        ok(defined $invocant, 'MethodCall chain: invocant is defined');
        is($invocant->class(), 'MethodCallExpr', 'MethodCall chain: invocant is MethodCallExpr');
        is($invocant->inputs()->[1]->value(), 'foo', 'MethodCall chain: inner method is foo');
    };
}

# === Subscript base expression capture ===
# Subscript grammar: Expression _ /->/ _ /\{/ _ Expression _ /\}/
# The base Expression must be captured as the target of SubscriptExpr.

{
    subtest 'Subscript captures target' => sub {
        my $ir = parse_source('$h->{key};');
        ok(defined $ir, 'Subscript: parses');

        my $stmts = get_all_stmts($ir);
        is(scalar $stmts->@*, 1, 'Subscript: one statement');

        my $sub = $stmts->[0];
        is($sub->class(), 'SubscriptExpr', 'Subscript: class');

        my $target = $sub->inputs()->[0];
        ok(defined $target, 'Subscript: target is defined');
        is($target->value(), '$h', 'Subscript: target is $h');
    };
}

# === return scalar $ops->@* captures all parts ===

{
    subtest 'return scalar PostfixDeref' => sub {
        my $ir = parse_source('return scalar $ops->@*;');
        ok(defined $ir, 'return scalar deref: parses');

        my $stmts = get_all_stmts($ir);
        is(scalar $stmts->@*, 1, 'return scalar deref: one statement');

        my $ret = $stmts->[0];
        ok($ret isa Chalk::IR::Node::Return, 'return scalar deref: is Return CFG node');

        my $value = $ret->inputs()->[1];  # inputs[0]=control, inputs[1]=value
        ok(defined $value, 'return scalar deref: return value defined');
        is($value->class(), 'BuiltinCall', 'return scalar deref: value is BuiltinCall(scalar)');
        is($value->inputs()->[0]->value(), 'scalar', 'return scalar deref: builtin name');

        my $scalar_arg = $value->inputs()->[1]->[0];
        ok(defined $scalar_arg, 'return scalar deref: scalar arg defined');
        is($scalar_arg->class(), 'PostfixDerefExpr', 'return scalar deref: arg is PostfixDerefExpr');

        my $deref_target = $scalar_arg->inputs()->[0];
        ok(defined $deref_target, 'return scalar deref: deref target defined');
        is($deref_target->value(), '$ops', 'return scalar deref: deref target is $ops');
    };
}

# === push with method chain PostfixDeref: push $ops->@*, $other->ops()->@* ===
# Filter-gap merge can admit a derivation where MethodCallExpr wraps
# BuiltinCall instead of being a standalone argument. Verify the IR is
# correctly structured.

{
    subtest 'push with method-chain PostfixDeref arg' => sub {
        my $ir = parse_source('push $ops->@*, $other->ops()->@*;');
        ok(defined $ir, 'push method-deref: parses');

        SKIP: {
            skip 'push method-deref: no IR', 6 unless defined $ir;

            my $stmts = get_all_stmts($ir);
            is(scalar $stmts->@*, 1, 'push method-deref: one statement');

            my $call = $stmts->[0];
            is($call->class(), 'BuiltinCall', 'push method-deref: statement is BuiltinCall');
            is($call->inputs()->[0]->value(), 'push', 'push method-deref: builtin name');

            my $args = $call->inputs()->[1];
            is(scalar $args->@*, 2, 'push method-deref: 2 args');

            # First arg should be PostfixDerefExpr($ops, @)
            my $arg1 = $args->[0];
            is($arg1->class(), 'PostfixDerefExpr', 'push method-deref: arg1 is PostfixDerefExpr');

            # Second arg should be PostfixDerefExpr(MethodCallExpr($other, ops, []), @)
            my $arg2 = $args->[1];
            is($arg2->class(), 'PostfixDerefExpr', 'push method-deref: arg2 is PostfixDerefExpr');
        }
    };
}

# === Test: prefix builtins with subscripted args get correct IR ===
# _fix_postfix_chain handles SubscriptExpr(BuiltinCall(exists/delete, [var]), key, style)
# by pushing the subscript inward. The same corruption pattern occurs for all prefix
# builtins (defined, ref, scalar, etc.) and must be handled identically.
{
    my @builtins_with_subscript = (
        ['defined $arr[$i];', 'defined'],
        ['ref $arr[$i];', 'ref'],
        ['length $arr[$i];', 'length'],
        ['chr $arr[$i];', 'chr'],
    );

    for my $case (@builtins_with_subscript) {
        my ($code, $builtin_name, $expected_style) = $case->@*;
        my $ir = parse_source($code);
        ok(defined $ir, "$builtin_name subscript: parses");

        SKIP: {
            skip "$builtin_name did not parse", 2 unless defined $ir;

            # Find the BuiltinCall in the top-level statement
            my $stmts = get_all_stmts($ir);
            my $stmt = $stmts->[0];
            ok(defined $stmt, "$builtin_name subscript: has statement");

            # The statement should be BuiltinCall, NOT SubscriptExpr wrapping it
            if ($stmt isa Chalk::IR::Node::Constructor) {
                is($stmt->class(), 'BuiltinCall',
                    "$builtin_name subscript: top-level is BuiltinCall (not SubscriptExpr)");

                # Verify the arg is a SubscriptExpr
                if ($stmt->class() eq 'BuiltinCall') {
                    my $args = $stmt->inputs()->[1];
                    ok(ref($args) eq 'ARRAY' && $args->@* > 0,
                        "$builtin_name subscript: has arguments");
                    if (ref($args) eq 'ARRAY' && $args->@* > 0
                        && $args->[0] isa Chalk::IR::Node::Constructor) {
                        is($args->[0]->class(), 'SubscriptExpr',
                            "$builtin_name subscript: arg is SubscriptExpr");
                    }
                }
            } else {
                fail("$builtin_name subscript: expected Constructor node");
            }
        }
    }
}

done_testing();
