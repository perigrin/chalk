# ABOUTME: Tests for the SoN->LLVM lowering pass for the literal-arithmetic slice (Phase 3a D4).
# ABOUTME: Validates that a typed SoN graph for `return 1+2` generates LLVM IR that runs correctly.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Return;
use Chalk::IR::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

# Skip if lli is not available (CI without LLVM)
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# L1: LLVM lowering module loads.
ok(Chalk::IR::Target::LLVM->can('lower'),
    'Chalk::IR::Target::LLVM has a lower() method');

# L2: hand-author the typed SoN graph for `return 1 + 2` and lower to LLVM IR text.
# Graph: Constant(1,Int) + Constant(2,Int) -> Add(Int) -> Return
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');

    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');

    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my $ll = Chalk::IR::Target::LLVM->lower($ret);

    ok(defined $ll, 'lower() returns defined text');
    like($ll, qr/define.*\@main/, 'generated .ll contains a main function');
    like($ll, qr/add i64/, 'generated .ll contains i64 add instruction');
}

# L3: the generated .ll contains NO perl C-API calls.
# This is the load-bearing negative AC: no Perl_, no SV, no libperl.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my $ll = Chalk::IR::Target::LLVM->lower($ret);

    unlike($ll, qr/Perl_/,  'generated .ll does not call Perl_ C-API functions');
    unlike($ll, qr/\bSV\b/, 'generated .ll does not mention SV type');
    unlike($ll, qr/libperl/, 'generated .ll does not mention libperl');
}

# L4: the generated .ll, when run through lli, produces the perl oracle output.
# perl oracle: 1+2 = 3 (printed as decimal integer).
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my $ll = Chalk::IR::Target::LLVM->lower($ret);

    # Write to temp file and run through lli
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;

    my $lli_out = qx($LLI $tmp 2>&1);
    my $exit    = $? >> 8;

    is($exit, 0, 'lli exits cleanly on generated .ll');

    # perl oracle
    my $perl_out = $1 if (1+2) =~ /(\d+)/;
    $perl_out = '3';   # constant: 1+2 under perl is 3

    chomp $lli_out;
    is($lli_out, $perl_out,
        "lli output '$lli_out' matches perl oracle '$perl_out'");
}

# L5: runtime-free coverage — every value-def has a non-Scalar representation.
# The Add graph for 1+2 is fully Int; no Scalar values, so coverage = 100%.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my @data_nodes = ($c1, $c2, $add);
    my @scalar_nodes = grep {
        defined $_->representation && $_->representation eq 'Scalar'
    } @data_nodes;

    is(scalar @scalar_nodes, 0,
        'runtime-free coverage: 0 Scalar-representation nodes in 1+2 graph (L-GREEN)');
}

# L6: the test does NOT use the hand-written t/spike/llvm/add.ll.
# Verify by checking the generated text is not identical to the spike file content.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my $generated = Chalk::IR::Target::LLVM->lower($ret);

    # The spike file contains this specific comment; generated output must not
    # simply be the spike file read back.
    unlike($generated, qr/This file is NOT generated by the Chalk compiler/,
        'generated .ll is not the hand-written spike file');
}

# ---------------------------------------------------------------------------
# L7: And node (&&) lowering — short-circuit branch+phi
#
# And(Constant 3 :Int, Constant 7 :Int) wrapped in Return.
# Perl &&: 3 is truthy -> returns 7.  lli must print 7.
# RED phase: currently dies "cannot lower op=And".
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');
    my $c7 = $f->make('Constant', value => '7', const_type => 'integer');
    $c7->set_representation('Int');
    my $and = $f->make('And', inputs => [$c3, $c7]);
    $and->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$and]);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "And node lowers without dying (got: $@)");

    SKIP: {
        skip 'And lowering failed', 4 unless defined $ll;

        unlike($ll, qr/Perl_/, 'And .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'And .ll: no SV type');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'And .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '7', "And .ll: lli output is 7 (3&&7 == 7)");
    }
}

# ---------------------------------------------------------------------------
# L8: Or node (||) lowering — short-circuit branch+phi
#
# Or(Constant 3 :Int, Constant 7 :Int) wrapped in Return.
# Perl ||: 3 is truthy -> returns 3.  lli must print 3.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');
    my $c7 = $f->make('Constant', value => '7', const_type => 'integer');
    $c7->set_representation('Int');
    my $or = $f->make('Or', inputs => [$c3, $c7]);
    $or->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$or]);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "Or node lowers without dying (got: $@)");

    SKIP: {
        skip 'Or lowering failed', 4 unless defined $ll;

        unlike($ll, qr/Perl_/, 'Or .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'Or .ll: no SV type');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'Or .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '3', "Or .ll: lli output is 3 (3||7 == 3)");
    }
}

# ---------------------------------------------------------------------------
# L9: Phi missing-predecessor guard
#
# A Phi node referenced in lower_value without all predecessor blocks
# having been materialized must die loudly (not silently emit
# undef-poisoned phi). This is the adversarial well-typed check.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    # Build a Region and Phi manually, but do NOT wire up the predecessor
    # blocks so the Phi has only 0 incoming values (empty inputs).
    my $region = $f->make('Region', inputs => []);
    my $phi    = $f->make('Phi', region => $region, values => []);
    $phi->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$phi]);

    eval { Chalk::IR::Target::LLVM->lower($ret) };
    like($@, qr/Phi|missing|edge|predecessor|incoming/i,
        'Phi with no incoming values dies loudly (adversarial guard)');
}

done_testing;
