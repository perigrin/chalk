# ABOUTME: Tests Perl IR to XS compilation for Tier C files.
# ABOUTME: ConciseOp full behavioral equivalence; 4 other files compile + structural checks.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);

use lib 'lib';
use lib 't/bootstrap/lib';

# === Skip guards ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

# === Setup ===

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierCTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierCTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse file -> IR ===

my sub parse_file_ir($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result->[4];
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# === Helper to build, compile, load XS module ===

my sub build_and_load($ir, $module_name) {
    my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => $module_name,
    );
    my $dist = $xs_target->generate_distribution($ir);
    return (undef, "generate_distribution failed") unless ref($dist) eq 'HASH';

    my $tmpdir = tempdir(CLEANUP => 1);
    for my $path (sort keys $dist->%*) {
        my $full_path = "$tmpdir/$path";
        my $dir = dirname($full_path);
        make_path($dir) unless -d $dir;
        open(my $fh, '>:encoding(UTF-8)', $full_path)
            or die "Cannot write $full_path: $!";
        print $fh $dist->{$path};
        close $fh;
    }

    my $build_output = `cd "$tmpdir" && "$^X" Build.PL 2>&1 && "$^X" Build 2>&1`;
    my $exit = $? >> 8;
    return (undef, "Build failed (exit $exit): $build_output") if $exit != 0;

    unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
    eval "require $module_name";
    return (undef, "Load failed: $@") if $@;

    return ($dist, undef);
}

# ============================================================
# 1. ConciseOp.pm — 5 field readers (3 with defaults) + 2 methods
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/ConciseOp.pm');
    ok(defined $ir, 'ConciseOp: parse produces IR');

    SKIP: {
        skip 'ConciseOp: no IR', 18 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierC::ConciseOp';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'ConciseOp: XS builds') or do {
            diag $err;
            # Dump XS for debugging
            if (defined $dist) {
                for my $path (sort keys $dist->%*) {
                    diag "=== $path ===\n" . $dist->{$path} if $path =~ /\.xs$/;
                }
            }
            skip 'ConciseOp: build failed', 16;
        };

        # Structural: XS has method signatures
        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/to_string\(/, 'ConciseOp: XS has to_string method');
        like($xs_code, qr/structural_key\(/, 'ConciseOp: XS has structural_key method');
        # Methods should have real bodies (not just /* empty */)
        like($xs_code, qr/hv_fetch.*name/, 'ConciseOp: to_string accesses name field');
        like($xs_code, qr/hv_fetch.*arity/, 'ConciseOp: methods access arity field');

        # Behavioral: 5 field readers
        my $op = eval { $module->new(
            name => 'const', arity => '0',
            type_info => 'IV 42', flags => '', private => '/BARE',
        ) };
        is($@, '', 'ConciseOp: new() succeeds') or do {
            diag $@;
            skip 'ConciseOp: new failed', 11;
        };

        is($op->name(), 'const', 'ConciseOp: name reader');
        is($op->arity(), '0', 'ConciseOp: arity reader');
        is($op->type_info(), 'IV 42', 'ConciseOp: type_info reader');
        is($op->flags(), '', 'ConciseOp: flags reader');
        is($op->private(), '/BARE', 'ConciseOp: private reader');

        # Behavioral: method calls with if-conditions, regex, and capture vars.
        # Suppress eval_pv warnings about uninitialized $_ from regex matching.
        {
            local $SIG{__WARN__} = sub {
                my $msg = shift;
                warn $msg unless $msg =~ /Use of uninitialized value/;
            };

            is($op->to_string(), '<0>  const[IV 42] /BARE',
                'ConciseOp: to_string() with all fields');
            is($op->structural_key(), 'const:0:IV:/BARE',
                'ConciseOp: structural_key() extracts IV type prefix');

            my $op2 = $module->new(name => 'enter', arity => '0');
            is($op2->to_string(), '<0>  enter',
                'ConciseOp: to_string() without optional fields');
            is($op2->structural_key(), 'enter:0',
                'ConciseOp: structural_key() without optional fields');

            my $op3 = $module->new(
                name => 'padsv', arity => '0', type_info => '$x',
            );
            is($op3->structural_key(), 'padsv:0:$x',
                'ConciseOp: structural_key() non-const passes type_info through');

            my $op4 = $module->new(
                name => 'const', arity => '0', type_info => 'PV "hello"',
            );
            is($op4->structural_key(), 'const:0:PV',
                'ConciseOp: structural_key() extracts PV type prefix');
        }
    }
}

# ============================================================
# 2. ConciseTree.pm — field $ops = [], 4 methods
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/ConciseTree.pm');
    ok(defined $ir, 'ConciseTree: parse produces IR');

    SKIP: {
        skip 'ConciseTree: no IR', 13 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierC::ConciseTree';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'ConciseTree: XS builds') or do {
            diag $err;
            skip 'ConciseTree: build failed', 11;
        };

        # Structural checks on the XS file
        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'ConciseTree: XS has MODULE line');
        like($xs_code, qr/ops\(self\)/, 'ConciseTree: XS has ops reader');

        # Behavioral: new() with default empty ops
        my $tree = eval { $module->new() };
        is($@, '', 'ConciseTree: new() succeeds') or do {
            diag $@;
            skip 'ConciseTree: new failed', 9;
        };

        # ops() reader returns arrayref (field default [] now emitted in PM stub)
        my $ops = $tree->ops();
        is(ref($ops), 'ARRAY', 'ConciseTree: ops() returns arrayref');
        is(scalar($ops && ref($ops) eq 'ARRAY' ? $ops->@* : 0), 0,
            'ConciseTree: default ops is empty');

        # op_count()
        is($tree->op_count(), 0, 'ConciseTree: op_count() is 0 for empty tree');

        # push_op() with a real ConciseOp
        use Chalk::Bootstrap::ConciseOp;
        my $op1 = Chalk::Bootstrap::ConciseOp->new(
            name => 'enter', arity => '0',
        );
        eval { $tree->push_op($op1) };
        is($tree->op_count(), 1, 'ConciseTree: op_count() is 1 after push_op');

        my $op2 = Chalk::Bootstrap::ConciseOp->new(
            name => 'const', arity => '0', type_info => 'IV 42',
        );
        eval { $tree->push_op($op2) };
        is($tree->op_count(), 2, 'ConciseTree: op_count() is 2 after second push_op');

        SKIP: {
            skip 'XS codegen: to_exec_string/concat segfault due to PostfixDeref iteration and for-loop range issues', 5;

            # to_exec_string() renders numbered lines
            {
                local $SIG{__WARN__} = sub {
                    my $msg = shift;
                    warn $msg unless $msg =~ /Use of uninitialized value/;
                };
                my $exec = eval { $tree->to_exec_string() } // '';
                like($exec, qr/^1\s+.*enter/m,
                    'ConciseTree: to_exec_string() line 1 has enter');
                like($exec, qr/^2\s+.*const/m,
                    'ConciseTree: to_exec_string() line 2 has const');
            }

            # concat() merges another tree's ops
            use Chalk::Bootstrap::ConciseTree;
            my $tree2 = Chalk::Bootstrap::ConciseTree->new();
            my $op3 = Chalk::Bootstrap::ConciseOp->new(
                name => 'leave', arity => '0',
            );
            $tree2->push_op($op3);
            eval { $tree->concat($tree2) };
            is($tree->op_count(), 3, 'ConciseTree: op_count() is 3 after concat');

            # Verify ops are in order after concat
            my @ops_list = $tree->ops() && ref($tree->ops()) eq 'ARRAY'
                ? $tree->ops()->@* : ();
            my @names = map { $_->name() } @ops_list;
            is_deeply(\@names, ['enter', 'const', 'leave'],
                'ConciseTree: ops in correct order after push_op + concat');
        }
    }
}

# ============================================================
# 3. Comparator.pm — compare and normalize methods
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/ConciseTree/Comparator.pm');
    ok(defined $ir, 'Comparator: parse produces IR');

    SKIP: {
        skip 'Comparator: no IR', 11 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierC::Comparator';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Comparator: XS builds') or do {
            diag $err;
            skip 'Comparator: build failed', 9;
        };

        # Structural check
        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        like($dist->{$xs_file}, qr/MODULE\s*=/, 'Comparator: XS has MODULE line');

        my $cmp = eval { $module->new() };
        is($@, '', 'Comparator: new() succeeds') or do {
            diag $@;
            skip 'Comparator: new failed', 8;
        };

        # Behavioral tests — XS method bodies for compare/normalize have
        # complex patterns (for loops, push, sprintf, regex substitution)
        # that the XS emitter doesn't handle yet. These can segfault, so
        # skip entirely until the emitter is fixed.
        SKIP: {
            skip 'TODO: XS emitter cannot compile compare/normalize method bodies yet', 8;

            # Build two identical trees and compare
            my $tree_a = Chalk::Bootstrap::ConciseTree->new();
            $tree_a->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'enter', arity => '0',
            ));
            $tree_a->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'const', arity => '0', type_info => 'IV 42',
            ));

            my $tree_b = Chalk::Bootstrap::ConciseTree->new();
            $tree_b->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'enter', arity => '0',
            ));
            $tree_b->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'const', arity => '0', type_info => 'IV 42',
            ));

            my $result = $cmp->compare($tree_a, $tree_b);
            ok(ref($result) eq 'HASH', 'Comparator: compare() returns hashref');
            ok($result->{match}, 'Comparator: identical trees match');
            is(scalar $result->{differences}->@*, 0,
                'Comparator: no differences for identical trees');

            # Build differing trees and compare
            my $tree_c = Chalk::Bootstrap::ConciseTree->new();
            $tree_c->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'enter', arity => '0',
            ));
            $tree_c->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'padsv', arity => '0', type_info => '$x',
            ));

            my $diff_result = $cmp->compare($tree_a, $tree_c);
            ok(!$diff_result->{match}, 'Comparator: different trees do not match');
            ok(scalar $diff_result->{differences}->@* > 0,
                'Comparator: differences reported for non-matching trees');

            # Op count mismatch
            my $tree_d = Chalk::Bootstrap::ConciseTree->new();
            $tree_d->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'enter', arity => '0',
            ));
            my $count_result = $cmp->compare($tree_a, $tree_d);
            ok(!$count_result->{match}, 'Comparator: count mismatch detected');
            like($count_result->{differences}->[0], qr/count mismatch/i,
                'Comparator: reports op count mismatch');

            # Normalize strips pad slot numbers
            my $tree_pad = Chalk::Bootstrap::ConciseTree->new();
            $tree_pad->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'padsv', arity => '0', type_info => '$x:3,4',
            ));
            my $normalized = $cmp->normalize($tree_pad);
            is($normalized->ops()->[0]->type_info(), '$x',
                'Comparator: normalize() strips pad slot numbers');
        }
    }
}

# ============================================================
# 4. Oracle.pm — concise_for, parse_concise_output
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/ConciseTree/Oracle.pm');
    ok(defined $ir, 'Oracle: parse produces IR');

    SKIP: {
        skip 'Oracle: no IR', 10 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierC::Oracle';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Oracle: XS builds') or do {
            diag $err;
            skip 'Oracle: build failed', 8;
        };

        # Structural check
        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        like($dist->{$xs_file}, qr/MODULE\s*=/, 'Oracle: XS has MODULE line');

        my $oracle = eval { $module->new() };
        is($@, '', 'Oracle: new() succeeds') or do {
            diag $@;
            skip 'Oracle: new failed', 7;
        };

        # Behavioral tests — XS method bodies for parse_concise_output
        # use for loops, split, regex, next unless that the emitter doesn't
        # handle yet. These can segfault, so skip until the emitter is fixed.
        SKIP: {
            skip 'TODO: XS emitter cannot compile parse_concise_output method body yet', 7;

            # parse_concise_output() with synthetic B::Concise -exec output
            my $concise_text = <<'CONCISE';
1  <0> enter
2  <;> nextstate(main 1 -e:1)
3  <$> const[IV 42]
4  <1> print sK/VOID
5  <@> leave[1 ref] vKP/REFC
CONCISE

            my $tree = $oracle->parse_concise_output($concise_text);
            ok(defined $tree, 'Oracle: parse_concise_output returns defined');
            is($tree->op_count(), 5,
                'Oracle: parsed 5 ops from concise output');

            # Verify parsed op details
            my $ops = $tree->ops();
            is($ops->[0]->name(), 'enter', 'Oracle: op 1 is enter');
            is($ops->[1]->name(), 'nextstate', 'Oracle: op 2 is nextstate');
            is($ops->[2]->name(), 'const', 'Oracle: op 3 is const');
            is($ops->[2]->type_info(), 'IV 42', 'Oracle: const has type_info IV 42');
            is($ops->[3]->name(), 'print', 'Oracle: op 4 is print');
        }
    }
}

# ============================================================
# 5. Context.pm — extract, extend, duplicate, leaves, scanned_text
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Context.pm');
    ok(defined $ir, 'Context: parse produces IR');

    SKIP: {
        skip 'Context: no IR', 16 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierC::Context';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Context: XS builds') or do {
            diag $err;
            skip 'Context: build failed', 14;
        };

        # Structural check
        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        like($dist->{$xs_file}, qr/MODULE\s*=/, 'Context: XS has MODULE line');

        # Basic construction with focus
        my $ctx = eval { $module->new(focus => 'hello') };
        is($@, '', 'Context: new(focus) succeeds') or do {
            diag $@;
            skip 'Context: new failed', 12;
        };

        # Field readers
        is($ctx->focus(), 'hello', 'Context: focus() reader');
        is($ctx->rule(), undef, 'Context: rule() defaults to undef');

        # extract() returns field value, defaults populated in PM stub new()
        is($ctx->extract(), 'hello', 'Context: extract() returns focus');
        is(ref($ctx->children()), 'ARRAY', 'Context: children() returns arrayref');
        is($ctx->position(), 0, 'Context: position() defaults to 0');

        # Behavioral tests for extend/duplicate/scanned_text/leaves —
        # XS method bodies use coderef invocation, recursion, isa operator,
        # conditional push. These can segfault, so skip until the emitter is fixed.
        SKIP: {
            skip 'TODO: XS emitter cannot compile extend/duplicate/leaves/scanned_text yet', 8;

            # extend() applies function and returns new context
            my $extended = $ctx->extend(sub ($c) { return uc($c->extract()) });
            is($extended->extract(), 'HELLO',
                'Context: extend() applies function to produce new focus');
            is($ctx->extract(), 'hello',
                'Context: original context unchanged after extend');

            # duplicate() wraps context in context
            my $duped = $ctx->duplicate();
            ok(defined $duped, 'Context: duplicate() returns defined');
            # duplicate returns a context whose focus is the original context
            my $inner = $duped->extract();
            ok(ref($inner), 'Context: duplicate() focus is a reference');

            # scanned_text() on a string-focus leaf
            is($ctx->scanned_text(), 'hello',
                'Context: scanned_text() returns string focus');

            # scanned_text() on a tree with children
            my $child1 = $module->new(focus => 'foo');
            my $child2 = $module->new(focus => 'bar');
            my $parent = $module->new(
                focus    => undef,
                children => [$child1, $child2],
            );
            is($parent->scanned_text(), 'foobar',
                'Context: scanned_text() concatenates children');

            # leaves() on a leaf returns itself
            my @leaf_results = $ctx->leaves();
            is(scalar @leaf_results, 1,
                'Context: leaves() on leaf returns 1 result');

            # leaves() on an intermediate node recurses into children
            my @parent_leaves = $parent->leaves();
            is(scalar @parent_leaves, 2,
                'Context: leaves() on parent returns 2 child leaves');
        }
    }
}

done_testing();
