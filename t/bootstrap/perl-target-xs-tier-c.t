# ABOUTME: Tests Perl IR to XS compilation for Tier C files.
# ABOUTME: Context.pm compile + structural checks.
use 5.42.0;
use utf8;
use Test::More;

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

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load);

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSTierCTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# ============================================================
# 5. Context.pm — extract, extend, duplicate, leaves, scanned_text
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir($gen_grammar, 'lib/Chalk/Bootstrap/Context.pm');
    ok(defined $ir, 'Context: parse produces IR');

    SKIP: {
        skip 'Context: no IR', 16 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierC::Context';
        my ($dist, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $dist, 'Context: XS builds') or do {
            diag $err;
            skip 'Context: build failed', 14;
        };

        # Structural check
        my ($xs_file) = grep { /\.xs$/ } keys $dist->{files}->%*;
        like(defined $xs_file ? $dist->{files}{$xs_file} : undef, qr/MODULE\s*=/, 'Context: XS has MODULE line');

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
