# ABOUTME: Tests the loader patches forward-referenced Phi backedges (loop graphs, RC2b).
# ABOUTME: A loop's Phi<->backedge data cycle forces one forward ref in any JSON node order.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
use JSON::PP;
use File::Temp qw(tempfile);

use Chalk::IR::Serialize::JSON ();

# A while loop's header Phi consumes its backedge value (Add/Subtract) and the
# backedge value consumes the Phi -- a genuine data cycle, so ANY serialization
# order leaves one input pointing forward. The loader resolves inputs single-
# pass (earlier nodes only), so a forward index must be deferred: construct the
# Phi with its init input, then wire inputs[1] via set_backedge once the
# referenced node exists. A wire v2 Loop's back control (its test's Proj 0) is
# the other forward reference, patched the same way.
#
# The graph is B::SoN's wire (writer loop-my-fresh, `-MO=-q,SoN,json`; the
# `classes` table dropped) for the corpus control-flow.md D2 contract:
#   my $n = 3; my $s = 0; while ($n > 0) { $s += $n; $n-- } print "[$s]\n";
# (The hand-built graph it replaces pinned the loop's Projs on the Loop, with
# no If and no back control -- a pre-v2 shape T2 refuses by name, "a loop whose
# test is pinned on it"; a skip_all after that failed assertion hid it.)

my $json = JSON::PP->new->encode({
    version => 2,
    source  => 'loop-backedge',
    dowarn  => { all_off => JSON::PP::false, all_on => JSON::PP::false, on => JSON::PP::false },
    marks   => { mem_operand => JSON::PP::true },
    methods => {
        'main::__PROGRAM__' => {
            start   => 0,
            returns => [18],
            nodes   => [
                { id => 0,  op => 'Start', inputs => [] },
                { id => 1,  op => 'Constant', inputs => [], stamp => 'Undef',
                  fields => { const_type => 'undef', value => undef } },
                { id => 2,  op => 'Constant', inputs => [], stamp => 'Str',
                  fields => { const_type => 'string', value => '[' } },
                { id => 3,  op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { const_type => 'integer', value => '0' } },
                # back control: the test's Proj 0 (id 19, FORWARD reference)
                { id => 4,  op => 'Loop', inputs => [0, 19], fields => { bound => 'each' } },
                # $s phi: init 0, backedge Add (id 22, FORWARD reference)
                { id => 5,  op => 'Phi', inputs => [3, 22], stamp => 'Int', fields => { region => 4 } },
                { id => 6,  op => 'Coerce', inputs => [5], stamp => 'Str',
                  fields => { from_repr => 'Int', to_repr => 'Str' } },
                { id => 7,  op => 'Concat', inputs => [2, 6], stamp => 'Str' },
                { id => 8,  op => 'Constant', inputs => [], stamp => 'Str',
                  fields => { const_type => 'string', value => "]\n" } },
                { id => 9,  op => 'Concat', inputs => [7, 8], stamp => 'Str' },
                { id => 10, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { const_type => 'integer', value => '3' } },
                # $n phi: init 3, backedge Subtract (id 21, FORWARD reference)
                { id => 11, op => 'Phi', inputs => [10, 21], stamp => 'Int', fields => { region => 4 } },
                { id => 12, op => 'NumGt', inputs => [11, 3], stamp => 'Boolean' },
                # the loop's test: an If on the Loop, its Projs the body (0) and the exit (1)
                { id => 13, op => 'If', inputs => [4, 12], control_in => 4 },
                { id => 14, op => 'Proj', inputs => [13], fields => { index => 1 } },
                { id => 15, op => 'Region', inputs => [14], head => 4 },
                { id => 16, op => 'Print', inputs => [9], control_in => 15, stamp => 'Maybe[Boolean]' },
                { id => 17, op => 'MemStart', inputs => [] },
                { id => 18, op => 'Return', inputs => [1], control_in => 16, mem_in => 17,
                  fields => { implicit => JSON::PP::true } },
                { id => 19, op => 'Proj', inputs => [13], fields => { index => 0 } },
                { id => 20, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { const_type => 'integer', value => '1' } },
                { id => 21, op => 'Subtract', inputs => [11, 20], stamp => 'Int' },
                { id => 22, op => 'Add', inputs => [5, 11], stamp => 'Int' },
            ],
        },
    },
});

my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
my $g = $graphs->{'main::__PROGRAM__'};
my $ret = $g->returns->[0];

subtest 'forward-referenced backedges are patched onto the Phis' => sub {
    my ($print) = grep { $_->operation eq 'Print' } $g->nodes->@*;
    my $region = $print->control_in;
    is($region->operation, 'Region', 'the Print follows the exit Region');
    my $loop = $region->head;
    is($loop->operation, 'Loop', 'Region.head reaches the Loop');
    ok(defined $loop->inputs->[1], 'the Loop back control is wired (not undef)');
    is($loop->inputs->[1]->operation, 'Proj', 'the Loop back control is its test\'s Proj');

    my $s_phi = $print->inputs->[0]->inputs->[0]->inputs->[1]->inputs->[0];
    is($s_phi->operation, 'Phi', 'the printed value is the $s Phi');
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

subtest 'the loaded loop graph lowers and runs, printing 6' => sub {
    my $LLI = Chalk::CodeGen::Harness::LLI->path;
    require Chalk::Target::LLVM;

    my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    is($@, '', 'lower() does not die') or return;

    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print {$fh} $ll;
    close $fh;
    my $out = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    is($exit, 0, 'lli exits 0') or diag($out);
    is($out, '[6]', 'loop computes 6 (3+2+1)');
};

done_testing();
