# ABOUTME: Tests the loader patches forward-referenced Phi backedges (loop graphs, RC2b).
# ABOUTME: A loop's Phi<->backedge data cycle forces one forward ref in any JSON node order.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib';
use Chalk::IR::Serialize::JSON ();

# A while loop's header Phi consumes its backedge value (Add/Subtract) and the
# backedge value consumes the Phi -- a genuine data cycle, so ANY serialization
# order leaves one input pointing forward. The loader resolves inputs single-
# pass (earlier nodes only), so a forward index must be deferred: construct the
# Phi with its init input, then wire inputs[1] via set_backedge once the
# referenced node exists (the same post-construction patch the corpus builder
# uses for loop_backedge edges).
#
# Shape under test = the corpus control-flow.md D2 contract:
#   my $n = 3; my $s = 0; while ($n > 0) { $s += $n; $n-- } $s   => Int:6

my $json = JSON::PP->new->encode({
    version => 1,
    source  => 'loop-backedge',
    methods => {
        'main::f' => {
            start   => 0,
            returns => [13],
            nodes   => [
                { id => 0,  op => 'Start', cfg => JSON::PP::true, inputs => [] },
                { id => 1,  op => 'Loop',  cfg => JSON::PP::true, inputs => [0] },
                { id => 2,  op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 3, const_type => 'integer' } },
                { id => 3,  op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 0, const_type => 'integer' } },
                { id => 4,  op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 1, const_type => 'integer' } },
                # $n phi: init 3, backedge Subtract (id 8, FORWARD reference)
                { id => 5,  op => 'Phi', inputs => [2, 8], stamp => 'Int',
                  fields => { region => 1 } },
                # $s phi: init 0, backedge Add (id 9, FORWARD reference)
                { id => 6,  op => 'Phi', inputs => [3, 9], stamp => 'Int',
                  fields => { region => 1 } },
                # condition reads the $n phi (backend strategy 2)
                { id => 7,  op => 'NumGt', inputs => [5, 3], stamp => 'Boolean' },
                { id => 8,  op => 'Subtract', inputs => [5, 4], stamp => 'Int' },
                { id => 9,  op => 'Add', inputs => [6, 5], stamp => 'Int' },
                { id => 10, op => 'Proj', cfg => JSON::PP::true, inputs => [1],
                  fields => { index => 0 } },
                { id => 11, op => 'Proj', cfg => JSON::PP::true, inputs => [1],
                  fields => { index => 1 } },
                { id => 12, op => 'Region', cfg => JSON::PP::true, inputs => [11] },
                { id => 13, op => 'Return', cfg => JSON::PP::true, inputs => [12, 6] },
            ],
        },
    },
});

my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
my $g = $graphs->{'main::f'};
my $ret = $g->returns->[0];

subtest 'forward-referenced backedges are patched onto the Phis' => sub {
    my $region = $ret->control_in;
    is($region->operation, 'Region', 'Return control_in is the exit Region');
    is($region->head->operation, 'Loop', 'Region.head reaches the Loop');

    my $s_phi = $ret->inputs->[0];
    is($s_phi->operation, 'Phi', 'Return value is the $s Phi');
    ok(defined $s_phi->inputs->[1], '$s Phi backedge is wired (not undef)');
    is($s_phi->inputs->[1]->operation, 'Add', '$s Phi backedge is the Add');

    my ($n_phi) = grep { $_->operation eq 'Phi' && $_ != $s_phi } $g->nodes->@*;
    ok(defined $n_phi, 'found the $n Phi');
    ok(defined $n_phi->inputs->[1], '$n Phi backedge is wired (not undef)');
    is($n_phi->inputs->[1]->operation, 'Subtract', '$n Phi backedge is the Subtract');

    # The backedge patch must also register the consumer edge, or the
    # backend's use-def walks cannot see the cycle.
    my $add = $s_phi->inputs->[1];
    ok((grep { $_ == $s_phi } $add->consumers->@*),
        'Add lists the $s Phi as a consumer');
};

subtest 'the loaded loop graph lowers and runs to Int:6' => sub {
    my $LLI = '/usr/lib/llvm-15/bin/lli';
    plan skip_all => "lli not found at $LLI" unless -x $LLI;

    require Chalk::Target::LLVM;
    my $ll = eval { Chalk::Target::LLVM->lower($ret) };
    is($@, '', 'lower() does not die') or diag($@);
    plan skip_all => 'lowering failed' unless defined $ll;

    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print {$fh} $ll;
    close $fh;
    my $out = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    is($exit, 0, 'lli exits 0') or diag($out);
    is($out, 'Int:6', 'loop computes Int:6 (3+2+1)');
};

done_testing();
