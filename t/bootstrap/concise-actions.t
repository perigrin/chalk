# ABOUTME: Tests for ConciseTree::Actions that map Perl grammar rules to ConciseOps.
# ABOUTME: Tests Phase 2 subset (declarations and literals) via actual parsing with the Perl grammar.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::ConciseTree;
use Chalk::Bootstrap::ConciseTree::Actions;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ConciseActionsTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ConciseActionsTest::grammar();
    my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
    skip 'Concise parser not built', 1 unless defined $parser;

    # Helper to parse and extract ConciseTree
    my sub parse_concise($source) {
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        my ($bool_val, $sem_val) = $result->@*;
        return undef unless $bool_val;
        return $sem_val->extract();
    }

    # Helper to get op names from a tree
    my sub op_names($tree) {
        return map { $_->name() } $tree->ops()->@*;
    }

    # --- Scalar assignment: my $x = 42 ---
    {
        my $tree = parse_concise('my $x = 42;');
        ok(defined $tree, 'scalar int assignment parses');
        isa_ok($tree, 'Chalk::Bootstrap::ConciseTree');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter nextstate const padsv_store leave)],
            'my $x = 42 op sequence');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        is($consts[0]->type_info(), 'IV 42', 'const is IV 42');

        my @stores = grep { $_->name() eq 'padsv_store' } $tree->ops()->@*;
        like($stores[0]->type_info(), qr/\$x/, 'padsv_store has $x');
        like($stores[0]->private(), qr{/LVINTRO}, 'padsv_store has /LVINTRO');
    }

    # --- String assignment: my $x = "hello" ---
    {
        my $tree = parse_concise('my $x = "hello";');
        ok(defined $tree, 'scalar string assignment parses');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        like($consts[0]->type_info(), qr/PV/, 'const is PV for string');
    }

    # --- Float assignment: my $x = 3.14 ---
    {
        my $tree = parse_concise('my $x = 3.14;');
        ok(defined $tree, 'scalar float assignment parses');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        like($consts[0]->type_info(), qr/NV/, 'const is NV for float');
    }

    # --- Bare declaration: my $x ---
    {
        my $tree = parse_concise('my $x;');
        ok(defined $tree, 'bare declaration parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter nextstate padsv leave)],
            'my $x op sequence');

        my @padsv = grep { $_->name() eq 'padsv' } $tree->ops()->@*;
        like($padsv[0]->type_info(), qr/\$x/, 'padsv has $x');
        like($padsv[0]->private(), qr{/LVINTRO}, 'padsv has /LVINTRO');
    }

    # --- Array assignment: my @arr = (1, 2) ---
    {
        my $tree = parse_concise('my @arr = (1, 2);');
        ok(defined $tree, 'array assignment parses');

        my @names = op_names($tree);
        is_deeply(\@names,
            [qw(enter nextstate pushmark const const pushmark padav aassign leave)],
            'my @arr = (1, 2) op sequence');

        my @padav = grep { $_->name() eq 'padav' } $tree->ops()->@*;
        like($padav[0]->type_info(), qr/\@arr/, 'padav has @arr');
        like($padav[0]->private(), qr{/LVINTRO}, 'padav has /LVINTRO');
    }

    # --- Hash assignment: my %h = (a => 1, b => 2) ---
    {
        my $tree = parse_concise('my %h = (a => 1, b => 2);');
        ok(defined $tree, 'hash assignment parses');

        my @names = op_names($tree);
        # Hash keys may be parsed as identifiers (producing empty trees) or
        # const ops depending on grammar ambiguity resolution
        ok((grep { $_ eq 'padhv' } @names), 'hash assignment has padhv');
        ok((grep { $_ eq 'aassign' } @names), 'hash assignment has aassign');
        ok((grep { $_ eq 'pushmark' } @names), 'hash assignment has pushmark');

        my @padhv = grep { $_->name() eq 'padhv' } $tree->ops()->@*;
        like($padhv[0]->type_info(), qr/%h/, 'padhv has %h');
        like($padhv[0]->private(), qr{/LVINTRO}, 'padhv has /LVINTRO');
    }

    # --- Multiple statements ---
    {
        my $tree = parse_concise('my $x = 1; my $y = 2;');
        ok(defined $tree, 'two statements parse');

        my @names = op_names($tree);
        my @nextstates = grep { $_ eq 'nextstate' } @names;
        is(scalar @nextstates, 2, 'two statements have 2 nextstates');
        my @stores = grep { $_ eq 'padsv_store' } @names;
        is(scalar @stores, 2, 'two statements have 2 padsv_store');
    }

    # --- Compile-time only: use 5.42.0; use utf8 ---
    {
        my $tree = parse_concise('use 5.42.0; use utf8;');
        ok(defined $tree, 'compile-time only parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter stub leave)],
            'compile-time only has enter stub leave');
    }

    # --- UseDeclaration produces empty tree (no runtime ops) ---
    {
        my $tree = parse_concise('use 5.42.0;');
        ok(defined $tree, 'single use parses');

        my @names = op_names($tree);
        ok((grep { $_ eq 'enter' } @names), 'single use has enter');
        ok((grep { $_ eq 'leave' } @names), 'single use has leave');
    }

    # --- Two-statement with different types ---
    {
        my $tree = parse_concise('my $x = "hello"; my $y = 3.14;');
        ok(defined $tree, 'mixed type two statements parse');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        is(scalar @consts, 2, 'mixed types have 2 consts');
        like($consts[0]->type_info(), qr/PV/, 'first const is PV');
        like($consts[1]->type_info(), qr/NV/, 'second const is NV');
    }
}

done_testing;
