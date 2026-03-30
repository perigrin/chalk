# ABOUTME: Tests Perl IR to Perl source code emission for Tier C files.
# ABOUTME: Validates generated Perl compiles, evals, and behaves equivalently.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPerlHelpers qw(setup_perl_grammar parse_and_generate eval_module);

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_perl_grammar('Chalk::Grammar::Perl::TargetPerlTierCTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# ============================================================
# 1. ConciseOp.pm — 5 fields, 2 methods (to_string, structural_key)
# ============================================================

{
    my $code = parse_and_generate($gen_grammar, 'lib/Chalk/Bootstrap/ConciseOp.pm');
    ok(defined $code, 'ConciseOp.pm: generated Perl code');

    SKIP: {
        skip 'ConciseOp.pm: no code generated', 12 unless defined $code;

        like($code, qr/field \$name/, 'ConciseOp.pm: has field $name');
        like($code, qr/field \$arity/, 'ConciseOp.pm: has field $arity');
        like($code, qr/field \$type_info/, 'ConciseOp.pm: has field $type_info');
        like($code, qr/method to_string/, 'ConciseOp.pm: has method to_string');
        like($code, qr/method structural_key/, 'ConciseOp.pm: has method structural_key');

        # Rename and eval — with cfg_lookup fix, the complete class is emitted
        # and compiles correctly.
        my ($ok, $err) = eval_module($code,
            'Chalk::Bootstrap::ConciseOp',
            'Chalk::Bootstrap::ConciseOpGenerated');
        ok($ok, 'ConciseOp.pm: evals cleanly') or diag "Error: $err";

        SKIP: {
            # Check if eval succeeded by trying to use the class
            my $eval_ok = eval { Chalk::Bootstrap::ConciseOpGenerated->can('new') };
            skip 'ConciseOp.pm: eval not yet supported', 5 unless $eval_ok;

            my $op = Chalk::Bootstrap::ConciseOpGenerated->new(
                name => 'const', arity => '0',
                type_info => 'IV 42', flags => '', private => '/BARE',
            );
            is($op->name(), 'const', 'ConciseOp.pm: name reader works');
            is($op->arity(), '0', 'ConciseOp.pm: arity reader works');

            # Test to_string
            my $str = $op->to_string();
            like($str, qr/const/, 'ConciseOp.pm: to_string includes op name');
            like($str, qr/IV 42/, 'ConciseOp.pm: to_string includes type_info');

            # Test structural_key
            my $key = $op->structural_key();
            like($key, qr/const/, 'ConciseOp.pm: structural_key includes op name');
        }
    }
}

# ============================================================
# 2. ConciseTree.pm — field $ops = [], 4 methods
# ============================================================

{
    my $code = parse_and_generate($gen_grammar, 'lib/Chalk/Bootstrap/ConciseTree.pm');
    ok(defined $code, 'ConciseTree.pm: generated Perl code');

    SKIP: {
        skip 'ConciseTree.pm: no code generated', 10 unless defined $code;

        like($code, qr/field \$ops/, 'ConciseTree.pm: has field $ops');
        like($code, qr/method push_op/, 'ConciseTree.pm: has method push_op');
        like($code, qr/method concat/, 'ConciseTree.pm: has method concat');
        like($code, qr/method to_exec_string/, 'ConciseTree.pm: has method to_exec_string');
        like($code, qr/method op_count/, 'ConciseTree.pm: has method op_count');

        # Rename and eval — with cfg_lookup fix, the complete class is emitted
        # and compiles correctly.
        my ($ok, $err) = eval_module($code,
            'Chalk::Bootstrap::ConciseTree',
            'Chalk::Bootstrap::ConciseTreeGenerated');
        ok($ok, 'ConciseTree.pm: evals cleanly') or diag "Error: $err";

        SKIP: {
            my $eval_ok = eval { Chalk::Bootstrap::ConciseTreeGenerated->can('new') };
            skip 'ConciseTree.pm: eval not yet supported', 3 unless $eval_ok;

            my $tree = Chalk::Bootstrap::ConciseTreeGenerated->new();
            is($tree->op_count(), 0, 'ConciseTree.pm: empty tree has 0 ops');

            use Chalk::Bootstrap::ConciseOp;
            my $op = Chalk::Bootstrap::ConciseOp->new(
                name => 'const', arity => '0',
            );
            $tree->push_op($op);
            is($tree->op_count(), 1, 'ConciseTree.pm: push_op increases count');

            my $str = $tree->to_exec_string();
            like($str, qr/const/, 'ConciseTree.pm: to_exec_string includes op name');
        }
    }
}

# ============================================================
# 3. Comparator.pm — compare and normalize methods
# ============================================================

{
    my $code = parse_and_generate($gen_grammar, 'lib/Chalk/Bootstrap/ConciseTree/Comparator.pm');
    ok(defined $code, 'Comparator.pm: generated Perl code');

    SKIP: {
        skip 'Comparator.pm: no code generated', 8 unless defined $code;

        like($code, qr/method compare/, 'Comparator.pm: has method compare');
        like($code, qr/method normalize/, 'Comparator.pm: has method normalize');

        # Rename and eval — the class compiles, but method bodies have
        # IR codegen bugs: HashRefExpr returns string instead of hashref,
        # postfix deref chaining ($tree->@*->ops()) is wrong.
        my ($ok, $err) = eval_module($code,
            'Chalk::Bootstrap::ConciseTree::Comparator',
            'Chalk::Bootstrap::ConciseTree::ComparatorGenerated');
        ok($ok, 'Comparator.pm: evals cleanly') or diag "Error: $err";

        SKIP: {
            my $eval_ok = eval { Chalk::Bootstrap::ConciseTree::ComparatorGenerated->can('new') };
            skip 'Comparator.pm: eval not yet supported', 4 unless $eval_ok;

            # Behavioral tests wrapped in TODO — generated code compiles but
            # has runtime bugs: compare() returns string 'match' instead of
            # hashref, normalize() uses wrong deref chain ($tree->@*->ops()).
            TODO: {
                local $TODO = 'return { key => val } parsed as Block not HashConstructor (#673)';
                my $cmp = Chalk::Bootstrap::ConciseTree::ComparatorGenerated->new();
                use Chalk::Bootstrap::ConciseOp;
                my $op1 = Chalk::Bootstrap::ConciseOp->new(
                    name => 'const', arity => '0', type_info => 'IV 42',
                );
                use Chalk::Bootstrap::ConciseTree;
                my $tree1 = Chalk::Bootstrap::ConciseTree->new(ops => [$op1]);
                my $tree2 = Chalk::Bootstrap::ConciseTree->new(ops => [$op1]);
                my $result = eval { Chalk::Bootstrap::ConciseTree::ComparatorGenerated->new()->compare($tree1, $tree2) };
                ok(ref($result) eq 'HASH' && $result->{match}, 'Comparator.pm: identical trees match');

                my $norm = eval { Chalk::Bootstrap::ConciseTree::ComparatorGenerated->new()->normalize($tree1) };
                ok(defined $norm, 'Comparator.pm: normalize returns a tree');
                is(eval { $norm->op_count() } // -1, 1, 'Comparator.pm: normalized tree has 1 op');

                my $op2 = Chalk::Bootstrap::ConciseOp->new(
                    name => 'padsv', arity => '0',
                );
                my $tree3 = Chalk::Bootstrap::ConciseTree->new(ops => [$op2]);
                my $result2 = eval { Chalk::Bootstrap::ConciseTree::ComparatorGenerated->new()->compare($tree1, $tree3) };
                ok(ref($result2) eq 'HASH' && !$result2->{match}, 'Comparator.pm: different trees do not match');
            }
        }
    }
}

# ============================================================
# 4. Oracle.pm — concise_for, parse_concise_output
# ============================================================

{
    my $code = parse_and_generate($gen_grammar, 'lib/Chalk/Bootstrap/ConciseTree/Oracle.pm');
    ok(defined $code, 'Oracle.pm: generated Perl code');

    SKIP: {
        skip 'Oracle.pm: no code generated', 6 unless defined $code;

        like($code, qr/method concise_for/, 'Oracle.pm: has method concise_for');
        like($code, qr/method parse_concise_output/, 'Oracle.pm: has method parse_concise_output');

        # Rename and eval — class compiles but method bodies have IR codegen
        # bugs (regex captures, split patterns, backtick expressions).
        my ($ok, $err) = eval_module($code,
            'Chalk::Bootstrap::ConciseTree::Oracle',
            'Chalk::Bootstrap::ConciseTree::OracleGenerated');
        ok($ok, 'Oracle.pm: evals cleanly') or diag "Error: $err";

        SKIP: {
            my $eval_ok = eval { Chalk::Bootstrap::ConciseTree::OracleGenerated->can('new') };
            skip 'Oracle.pm: eval not yet supported', 2 unless $eval_ok;

            # Behavioral tests for parse_concise_output
            {
                my $oracle = Chalk::Bootstrap::ConciseTree::OracleGenerated->new();
                my $sample = <<'CONCISE';
1     <0> enter
2     <;> nextstate(main 1 -e:1)
3     <0> const[IV 42]
4     <@> leave
CONCISE
                my $tree = eval { $oracle->parse_concise_output($sample) };
                ok(defined $tree, 'Oracle.pm: parse_concise_output returns a tree');
                is(eval { $tree->op_count() } // -1, 4, 'Oracle.pm: parsed 4 ops from sample');
            }
        }
    }
}

# ============================================================
# 5. Context.pm — extract, extend, duplicate, leaves, scanned_text
# ============================================================

{
    my $code = parse_and_generate($gen_grammar, 'lib/Chalk/Bootstrap/Context.pm');
    ok(defined $code, 'Context.pm: generated Perl code');

    SKIP: {
        skip 'Context.pm: no code generated', 10 unless defined $code;

        like($code, qr/method extract/, 'Context.pm: has method extract');
        like($code, qr/method extend/, 'Context.pm: has method extend');
        like($code, qr/method duplicate/, 'Context.pm: has method duplicate');
        like($code, qr/method leaves/, 'Context.pm: has method leaves');
        like($code, qr/method scanned_text/, 'Context.pm: has method scanned_text');

        # Rename and eval
        {
            my ($ok, $err) = eval_module($code,
                'Chalk::Bootstrap::Context',
                'Chalk::Bootstrap::ContextGenerated');
            ok($ok, 'Context.pm: evals cleanly') or diag "Error: $err";
        }

        SKIP: {
            my $eval_ok = eval { Chalk::Bootstrap::ContextGenerated->can('new') };
            skip 'Context.pm: eval not yet supported', 3 unless $eval_ok;

            my $ctx = Chalk::Bootstrap::ContextGenerated->new(focus => 'hello');
            is($ctx->extract(), 'hello', 'Context.pm: extract returns focus');

            my $ext = $ctx->extend(sub ($c) { return $c->extract() . ' world' });
            is($ext->extract(), 'hello world', 'Context.pm: extend applies function');

            my $scan_ctx = Chalk::Bootstrap::ContextGenerated->new(focus => 'foo');
            is($scan_ctx->scanned_text(), 'foo', 'Context.pm: scanned_text returns string focus');
        }
    }
}

done_testing();
