# ABOUTME: Reproducibility guardrail — the perl5-blead SHA the harvester corpus
# ABOUTME: is sourced from is pinned in exactly one place (HarvestPin) and drift is LOUD.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use File::Temp qw(tempdir);

binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use Chalk::CodeGen::Harness::HarvestPin;

my $P = 'Chalk::CodeGen::Harness::HarvestPin';

# --- The pin is recorded, and in exactly ONE place --------------------------
subtest 'the pinned perl5 SHA is 94e5086608, recorded in the module' => sub {
    is($P->pinned_sha, '94e5086608', 'HarvestPin holds the pinned blead SHA');

    # Single source of truth WITHIN THE HARNESS CODE: the pin literal appears in
    # exactly one t/lib file — HarvestPin.pm. (The PRD/plan docs under docs/plans
    # reference the SHA as issue specification; the guide doc note is prose, not
    # code. The invariant that guards against drift is: no second harness module
    # hard-codes the pin.)
    my $out = qx{grep -rl '94e5086608' t/lib 2>/dev/null};
    my @files = grep { length } split /\n/, $out;
    is_deeply(
        [ sort @files ],
        [ 't/lib/Chalk/CodeGen/Harness/HarvestPin.pm' ],
        'the pin literal lives in exactly one harness module (HarvestPin.pm)'
    ) or diag("pin literal found in: @files");
};

# --- verify_checkout distinguishes ok / mismatch / absent / dirty -----------

# helper: build a throwaway git repo at a known SHA (never touches ~/dev/perl5)
sub _make_repo {
    my ($sha_body) = @_;
    my $dir = tempdir(CLEANUP => 1);
    system("git -C $dir init -q");
    system("git -C $dir config user.email t\@t");
    system("git -C $dir config user.name t");
    open my $fh, '>', "$dir/f" or die $!;
    print {$fh} ($sha_body // "seed\n");
    close $fh;
    system("git -C $dir add f");
    system("git -C $dir commit -q -m seed");
    return $dir;
}

subtest 'ok: HEAD equals the pin' => sub {
    my $dir = _make_repo();
    my $head = qx{git -C $dir rev-parse HEAD}; chomp $head;

    # Pass the checkout's own HEAD as the expected pin -> must be ok.
    my $r = $P->verify_checkout($dir, expected_sha => $head);
    is($r->{status}, 'ok', 'matching HEAD reports ok');
    ok(!$r->{loud}, 'ok result is not loud');
};

subtest 'mismatch: HEAD differs from the pin is LOUD with both SHAs' => sub {
    my $dir  = _make_repo();
    my $head = qx{git -C $dir rev-parse HEAD}; chomp $head;

    my $r = $P->verify_checkout($dir, expected_sha => 'deadbeefcafe');
    is($r->{status}, 'mismatch', 'differing HEAD reports mismatch');
    ok($r->{loud}, 'mismatch is LOUD');
    like($r->{detail}, qr/\Q$head\E/,       'detail names the actual HEAD');
    like($r->{detail}, qr/deadbeefcafe/,     'detail names the expected pin');
};

subtest 'absent: a non-existent checkout is LOUD' => sub {
    my $r = $P->verify_checkout('/no/such/perl5/checkout/here');
    is($r->{status}, 'absent', 'missing checkout reports absent');
    ok($r->{loud}, 'absent is LOUD');
};

subtest 'dirty: a checkout with uncommitted changes is LOUD (must not harvest)' => sub {
    my $dir  = _make_repo();
    my $head = qx{git -C $dir rev-parse HEAD}; chomp $head;
    # dirty it
    open my $fh, '>>', "$dir/f" or die $!;
    print {$fh} "uncommitted\n";
    close $fh;

    my $r = $P->verify_checkout($dir, expected_sha => $head);
    is($r->{status}, 'dirty', 'a dirty tree reports dirty even when HEAD matches');
    ok($r->{loud}, 'dirty is LOUD');
};

# --- re-harvest is DELIBERATE: verify never regenerates/mutates -------------
subtest 're-harvest is not automatic — verify does not mutate the checkout' => sub {
    my $dir  = _make_repo();
    my $head = qx{git -C $dir rev-parse HEAD}; chomp $head;
    my $before = qx{git -C $dir status --porcelain};

    $P->verify_checkout($dir, expected_sha => $head);

    my $after = qx{git -C $dir status --porcelain};
    is($after, $before, 'verify_checkout left the tree untouched (no auto-regenerate)');

    ok(!$P->can('regenerate'), 'HarvestPin exposes no implicit regenerate method');
    ok(!$P->can('harvest'),    'HarvestPin exposes no implicit harvest method');
};

done_testing;
