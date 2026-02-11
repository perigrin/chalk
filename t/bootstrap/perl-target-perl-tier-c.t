# ABOUTME: Tests Perl IR to Perl source code emission for Tier C files.
# ABOUTME: Validates generated Perl compiles, evals, and behaves equivalently.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TargetPerlTierCTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::TargetPerlTierCTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper ===

my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();

my sub parse_and_generate($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result->[4];
    return undef unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return undef unless defined $ir;

    return $perl_target->generate($ir);
}

# ============================================================
# 1. ConciseOp.pm — 5 fields, 2 methods (to_string, structural_key)
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/Bootstrap/ConciseOp.pm');
    ok(defined $code, 'ConciseOp.pm: generated Perl code');

    SKIP: {
        skip 'ConciseOp.pm: no code generated', 12 unless defined $code;

        like($code, qr/field \$name/, 'ConciseOp.pm: has field $name');
        like($code, qr/field \$arity/, 'ConciseOp.pm: has field $arity');
        like($code, qr/field \$type_info/, 'ConciseOp.pm: has field $type_info');
        like($code, qr/method to_string/, 'ConciseOp.pm: has method to_string');
        like($code, qr/method structural_key/, 'ConciseOp.pm: has method structural_key');

        # Rename and eval
        my $renamed = $code;
        $renamed =~ s/Chalk::Bootstrap::ConciseOp\b/Chalk::Bootstrap::ConciseOpGenerated/g;
        eval $renamed;
        is($@, '', 'ConciseOp.pm: evals cleanly') or diag "Code:\n$renamed\nError: $@";

        SKIP: {
            skip 'ConciseOp.pm: eval failed', 5 if $@;

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
    my $code = parse_and_generate('lib/Chalk/Bootstrap/ConciseTree.pm');
    ok(defined $code, 'ConciseTree.pm: generated Perl code');

    SKIP: {
        skip 'ConciseTree.pm: no code generated', 10 unless defined $code;

        like($code, qr/field \$ops/, 'ConciseTree.pm: has field $ops');
        like($code, qr/method push_op/, 'ConciseTree.pm: has method push_op');
        like($code, qr/method concat/, 'ConciseTree.pm: has method concat');
        like($code, qr/method to_exec_string/, 'ConciseTree.pm: has method to_exec_string');
        like($code, qr/method op_count/, 'ConciseTree.pm: has method op_count');

        # Rename and eval — method bodies use PostfixDeref ($ops->@*) and
        # push/scalar builtins that fragment in the ambiguous grammar.
        # Behavioral equivalence deferred until PostfixDeref chaining is fixed.
        TODO: {
            local $TODO = 'Method bodies use PostfixDeref and builtins that fragment in ambiguous grammar';
            my $renamed = $code;
            $renamed =~ s/Chalk::Bootstrap::ConciseTree\b/Chalk::Bootstrap::ConciseTreeGenerated/g;
            eval $renamed;
            is($@, '', 'ConciseTree.pm: evals cleanly');
        }

        SKIP: {
            skip 'ConciseTree.pm: eval not yet supported', 3;

            my $tree = Chalk::Bootstrap::ConciseTreeGenerated->new();
            is($tree->op_count(), 0, 'ConciseTree.pm: empty tree has 0 ops');

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
    my $code = parse_and_generate('lib/Chalk/Bootstrap/ConciseTree/Comparator.pm');
    ok(defined $code, 'Comparator.pm: generated Perl code');

    SKIP: {
        skip 'Comparator.pm: no code generated', 8 unless defined $code;

        like($code, qr/method compare/, 'Comparator.pm: has method compare');
        like($code, qr/method normalize/, 'Comparator.pm: has method normalize');

        # Rename and eval — method bodies use sprintf, s///g, ternary, complex
        # method chains that fragment in the ambiguous grammar.
        TODO: {
            local $TODO = 'Method bodies use complex constructs that fragment in ambiguous grammar';
            my $renamed = $code;
            $renamed =~ s/Chalk::Bootstrap::ConciseTree::Comparator\b/Chalk::Bootstrap::ConciseTree::ComparatorGenerated/g;
            eval $renamed;
            is($@, '', 'Comparator.pm: evals cleanly');
        }

        SKIP: {
            skip 'Comparator.pm: eval not yet supported', 4;

            my $cmp = Chalk::Bootstrap::ConciseTree::ComparatorGenerated->new();
            my $op1 = Chalk::Bootstrap::ConciseOp->new(
                name => 'const', arity => '0', type_info => 'IV 42',
            );
            my $tree1 = Chalk::Bootstrap::ConciseTree->new(ops => [$op1]);
            my $tree2 = Chalk::Bootstrap::ConciseTree->new(ops => [$op1]);
            my $result = $cmp->compare($tree1, $tree2);
            ok($result->{match}, 'Comparator.pm: identical trees match');

            my $norm = $cmp->normalize($tree1);
            ok(defined $norm, 'Comparator.pm: normalize returns a tree');
            is($norm->op_count(), 1, 'Comparator.pm: normalized tree has 1 op');

            my $op2 = Chalk::Bootstrap::ConciseOp->new(
                name => 'padsv', arity => '0',
            );
            my $tree3 = Chalk::Bootstrap::ConciseTree->new(ops => [$op2]);
            my $result2 = $cmp->compare($tree1, $tree3);
            ok(!$result2->{match}, 'Comparator.pm: different trees do not match');
        }
    }
}

# ============================================================
# 4. Oracle.pm — concise_for, parse_concise_output
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/Bootstrap/ConciseTree/Oracle.pm');
    ok(defined $code, 'Oracle.pm: generated Perl code');

    SKIP: {
        skip 'Oracle.pm: no code generated', 6 unless defined $code;

        like($code, qr/method concise_for/, 'Oracle.pm: has method concise_for');
        like($code, qr/method parse_concise_output/, 'Oracle.pm: has method parse_concise_output');

        # Rename and eval — method bodies use backticks, split, complex regex,
        # next unless, captures that fragment in the ambiguous grammar.
        TODO: {
            local $TODO = 'Method bodies use backticks, regex, split that fragment in ambiguous grammar';
            my $renamed = $code;
            $renamed =~ s/Chalk::Bootstrap::ConciseTree::Oracle\b/Chalk::Bootstrap::ConciseTree::OracleGenerated/g;
            eval $renamed;
            is($@, '', 'Oracle.pm: evals cleanly');
        }

        SKIP: {
            skip 'Oracle.pm: eval not yet supported', 2;

            my $oracle = Chalk::Bootstrap::ConciseTree::OracleGenerated->new();
            my $sample = <<'CONCISE';
1     <0> enter
2     <;> nextstate(main 1 -e:1)
3     <0> const[IV 42]
4     <@> leave
CONCISE
            my $tree = $oracle->parse_concise_output($sample);
            ok(defined $tree, 'Oracle.pm: parse_concise_output returns a tree');
            is($tree->op_count(), 4, 'Oracle.pm: parsed 4 ops from sample');
        }
    }
}

# ============================================================
# 5. Context.pm — extract, extend, duplicate, leaves, scanned_text
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/Bootstrap/Context.pm');
    ok(defined $code, 'Context.pm: generated Perl code');

    SKIP: {
        skip 'Context.pm: no code generated', 10 unless defined $code;

        like($code, qr/method extract/, 'Context.pm: has method extract');
        like($code, qr/method extend/, 'Context.pm: has method extend');
        like($code, qr/method duplicate/, 'Context.pm: has method duplicate');
        like($code, qr/method leaves/, 'Context.pm: has method leaves');
        like($code, qr/method scanned_text/, 'Context.pm: has method scanned_text');

        # Rename and eval — method bodies use anon sub, isa operator, recursion,
        # ref(), PostfixDeref that fragment in the ambiguous grammar.
        TODO: {
            local $TODO = 'Method bodies use anon sub, isa, recursion, PostfixDeref that fragment';
            my $renamed = $code;
            $renamed =~ s/Chalk::Bootstrap::Context\b/Chalk::Bootstrap::ContextGenerated/g;
            eval $renamed;
            is($@, '', 'Context.pm: evals cleanly');
        }

        SKIP: {
            skip 'Context.pm: eval not yet supported', 3;

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
