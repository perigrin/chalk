# ABOUTME: Tests TernaryExpr lowers a non-Boolean condition via truthiness coercion
# ABOUTME: (icmp ne for Int), so bare-scalar guards ($x = 7 if $c) are lowerable.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Serialize::JSON ();

# A statement-modifier merge (`$x = 7 if $c`) and a plain ternary (`$c ? 7 : 9`)
# both put the raw guard value in TernaryExpr inputs[0]. Perl truthiness allows
# any scalar there; the select needs an i1, so an Int condition must coerce via
# icmp ne i64 (the same _ensure_i1 rule Not uses). Previously the raw i64
# reached `select i1` and lli rejected the module.

my $LLI = '/usr/lib/llvm-15/bin/lli';
plan skip_all => "lli not found at $LLI" unless -x $LLI;
require Chalk::Target::LLVM;

# Observe the value the way a program does: PRINT it, bracketed, then return
# undef. A program's contract is stdout plus exit status; it has no side
# channel that hands a value back to a harness. The Print is appended AFTER
# the graph's last existing effect, so the select under test still runs first.
sub print_returned_value ($f, $ret_node) {
    my $v    = $ret_node->inputs->[0];
    my $repr = $v->stamp;
    my $s    = $v;
    if (!defined $repr || $repr ne 'Str') {
        $s = $f->make('Coerce', inputs => [$v],
            from_repr => $repr, to_repr => 'Str');
        $s->set_stamp('Str');
    }

    my $open = $f->make('Constant', value => '[', const_type => 'string');
    $open->set_stamp('Str');
    my $close = $f->make('Constant', value => "]\n", const_type => 'string');
    $close->set_stamp('Str');

    my $ctrl = $ret_node->control_in // $f->make_cfg('Start');
    for my $part ($open, $s, $close) {
        my $p = $f->make('Print', inputs => [$part]);
        $p->set_control_in($ctrl);
        $ctrl = $p;
    }

    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$u]);
    $ret->set_control_in($ctrl);
    return $ret;
}

sub run_ternary ($cond_value) {
    my $json = JSON::PP->new->encode({
        version => 1,
        source  => 'ternary-truthiness',
        methods => {
            'main::f' => {
                start   => 0,
                returns => [5],
                nodes   => [
                    { id => 0, op => 'Start', cfg => JSON::PP::true, inputs => [] },
                    { id => 1, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => $cond_value, const_type => 'integer' } },
                    { id => 2, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 7, const_type => 'integer' } },
                    { id => 3, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 9, const_type => 'integer' } },
                    { id => 4, op => 'TernaryExpr', inputs => [1, 2, 3], stamp => 'Int' },
                    # Current wire shape: control rides control_in, NOT inputs[0].
                    # (Pre-perl5-son-344fc075 this was the flattened
                    # `inputs => [control, value]`; the loader has no reshape
                    # code for that any more, so a flattened fixture lowers
                    # Start as a value and dies.)
                    { id => 5, op => 'Return', cfg => JSON::PP::true,
                      inputs => [4], control_in => 0 },
                ],
            },
        },
    });
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $ret = $graphs->{'main::f'}->returns->[0];
    my $f = Chalk::IR::NodeFactory->new;
    my $ll = eval { Chalk::Target::LLVM->lower(print_returned_value($f, $ret), program_mode => 1) };
    return (undef, $@) if $@;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print {$fh} $ll;
    close $fh;
    my $out = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($exit == 0 ? $out : undef, $out);
}

subtest 'Int condition coerces to i1: truthy selects the true arm' => sub {
    my ($out, $diag) = run_ternary(5);
    is($out, '[7]', 'TernaryExpr(5, 7, 9) prints 7') or diag($diag);
};

subtest 'Int condition coerces to i1: zero selects the false arm' => sub {
    my ($out, $diag) = run_ternary(0);
    is($out, '[9]', 'TernaryExpr(0, 7, 9) prints 9') or diag($diag);
};

done_testing();
