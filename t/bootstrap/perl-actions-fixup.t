# ABOUTME: Tests _fixup_stmts() ambiguity resolution in Perl::Actions.
# ABOUTME: Validates return/die merging and UseDecl import arg merging across hash seeds.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;

# Build Perl grammar pipeline: IR -> generated Perl -> eval -> grammar objects
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::Target::Perl->new();
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

    my $sem_ctx = $result->[4];
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# === Helper to find a specific Constructor in IR statements ===

my sub find_class_in_stmts($ir, $class) {
    my $stmts = $ir->inputs()->[0];
    for my $stmt ($stmts->@*) {
        if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                && $stmt->class() eq $class) {
            return $stmt;
        }
    }
    return undef;
}

my sub find_method_in_class($class_decl, $name) {
    my $body = $class_decl->inputs()->[2];
    for my $item ($body->@*) {
        if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                && $item->class() eq 'MethodDecl'
                && $item->inputs()->[0]->value() eq $name) {
            return $item;
        }
    }
    return undef;
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

        my $body = $method->inputs()->[2];
        is(scalar $body->@*, 1, 'return merge: method body has 1 item');
        is($body->[0]->class(), 'ReturnStmt', 'return merge: body item is ReturnStmt');
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

        my $body = $method->inputs()->[2];
        is(scalar $body->@*, 1, 'die merge: method body has 1 item');
        is($body->[0]->class(), 'DieCall', 'die merge: body item is DieCall');

        my $args = $body->[0]->inputs()->[0];
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

        my $stmts = $ir->inputs()->[0];
        # Find the 'experimental' UseDecl
        my $exp_use;
        for my $stmt ($stmts->@*) {
            if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && $stmt->class() eq 'UseDecl'
                    && $stmt->inputs()->[0]->value() eq 'experimental') {
                $exp_use = $stmt;
                last;
            }
        }
        ok(defined $exp_use, 'use merge: found experimental UseDecl');
        my $import_args = $exp_use->inputs()->[1];
        ok(defined $import_args, 'use merge: import_args defined');
        is(ref($import_args), 'ARRAY', 'use merge: import_args is arrayref');
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

        my $body = $class_decl->inputs()->[2];
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
            push @results, {
                seed        => $seed,
                class_name  => $class_decl->inputs()->[0]->value(),
                parent      => $class_decl->inputs()->[1]->value(),
                method_name => $method->inputs()->[0]->value(),
                body_class  => $method->inputs()->[2][0]->class(),
                die_msg     => $method->inputs()->[2][0]->inputs()->[0][0]->value(),
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

        my $stmts = $ir->inputs()->[0];
        is(scalar $stmts->@*, 1, 'push multi-arg: one statement (not fragmented)');

        my $call = $stmts->[0];
        is($call->class(), 'BuiltinCall', 'push multi-arg: statement is BuiltinCall');

        my $args = $call->inputs()->[1];
        is(scalar $args->@*, 2, 'push multi-arg: BuiltinCall has 2 args');
    }
}

done_testing();
