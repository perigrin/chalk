# ABOUTME: Tests TernaryExpr lowers a non-Bool condition via truthiness coercion
# ABOUTME: (icmp ne for Int), so bare-scalar guards ($x = 7 if $c) are lowerable.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib';
use Chalk::IR::Serialize::JSON ();

# A statement-modifier merge (`$x = 7 if $c`) and a plain ternary (`$c ? 7 : 9`)
# both put the raw guard value in TernaryExpr inputs[0]. Perl truthiness allows
# any scalar there; the select needs an i1, so an Int condition must coerce via
# icmp ne i64 (the same _ensure_i1 rule Not uses). Previously the raw i64
# reached `select i1` and lli rejected the module.

my $LLI = '/usr/lib/llvm-15/bin/lli';
plan skip_all => "lli not found at $LLI" unless -x $LLI;
require Chalk::Target::LLVM;

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
                    { id => 5, op => 'Return', cfg => JSON::PP::true, inputs => [0, 4] },
                ],
            },
        },
    });
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $ret = $graphs->{'main::f'}->returns->[0];
    my $ll = eval { Chalk::Target::LLVM->lower($ret) };
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
    is($out, 'Int:7', 'TernaryExpr(5, 7, 9) runs to Int:7') or diag($diag);
};

subtest 'Int condition coerces to i1: zero selects the false arm' => sub {
    my ($out, $diag) = run_ternary(0);
    is($out, 'Int:9', 'TernaryExpr(0, 7, 9) runs to Int:9') or diag($diag);
};

done_testing();
