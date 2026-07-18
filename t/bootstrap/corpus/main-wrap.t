# ABOUTME: Proves the source-prep that wraps a top-level program body in sub __main__
# ABOUTME: yields faithful multi-statement lowering (3 Print nodes, lli stdout a\nb\nc\n).
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON ();
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::MainWrap qw(wrap_main);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# Emit B::SoN json for a full program string (already-prepped source).
# ---------------------------------------------------------------------------
sub bson_json ($prog) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $prog;
    close $fh;
    return qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
}

# The program body under test: three ordered top-level void prints. With I1
# (effect-by-default) + I2 (Print node), a SEQUENCE of void prints threads on
# the control chain in program order -- none dropped.
my $BODY = qq{print "a\\n"; print "b\\n"; print "c\\n";};

# ===========================================================================
# Layer 1 (documents-the-need): a BARE body (no sub) yields methods: {}.
# This is WHY the wrap exists -- B::SoN emits nothing for a top-level program
# body, so it must be wrapped in a synthetic sub before lowering.
# ===========================================================================
{
    my $bare_prog = "use 5.42.0;\npackage main;\n$BODY\n";
    my $json = bson_json($bare_prog);
    my $data = JSON::PP->new->decode($json);
    is_deeply($data->{methods}, {},
        'documents-the-need: unwrapped bare program body yields methods: {}');
}

# ===========================================================================
# The wrap: MainWrap turns a program-body string into sub __main__ { <body> }.
# ===========================================================================
my $wrapped = wrap_main($BODY);
like($wrapped, qr/\bsub\s+__main__\s*\{/,
    'wrap_main produces a sub __main__ { ... } wrapper');
like($wrapped, qr/\Q$BODY\E/,
    'wrap_main preserves the program body verbatim (no statement drop)');

my $prog = "use 5.42.0;\npackage main;\n$wrapped\n";

# ===========================================================================
# Layer 2 (graph): the wrapped 3-print body lowers to 3 control-threaded
# Print nodes -- none dropped. Inspect the loaded graph via from_json.
# ===========================================================================
my $json = bson_json($prog);
my $data = JSON::PP->new->decode($json);
ok($data->{methods}{'main::__main__'},
    'wrapped body produces a main::__main__ method (the sub name)');

my ($graphs, $mop) = Chalk::IR::Serialize::JSON::from_json($json);
my $g = $graphs->{'main::__main__'};
ok($g, 'loaded a graph for main::__main__');

my @prints = grep { $_->can('operation') && $_->operation eq 'Print' } $g->nodes->@*;
is(scalar(@prints), 3,
    'graph: wrapped 3-print body yields 3 Print nodes (none dropped)');

# ===========================================================================
# Layer 3 (behavioral): lli stdout for the wrapped 3-print body is a\nb\nc\n,
# NOT just c\n. This proves I1's effect-pinning cured the statement-drop.
# ===========================================================================
my $ret = $g->returns->[0];
ok($ret, 'graph has a Return node to lower from');

my $ll = Chalk::Target::LLVM->lower($ret, (defined $mop ? (mop => $mop) : ()));
my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
print $lfh $ll;
close $lfh;

my $out = qx($LLI $lltmp 2>&1);
my $exit = $? >> 8;
is($? & 127, 0, 'lli did not die on a signal');
is($exit, 0, 'lli exited 0');

# The three prints land BEFORE the return-value epilogue line; assert the
# stdout STARTS with a\nb\nc\n (the epilogue trails). The load-bearing proof:
# all three lines are present and ORDERED, not just the last one (c\n).
like($out, qr/\Aa\nb\nc\n/,
    'behavioral: lli stdout is a\nb\nc\n (all three, ordered) -- NOT just c\n');
unlike($out, qr/\Ac\n/,
    'behavioral: lli stdout is NOT just c\n (no last-statement-only drop)');

done_testing();
