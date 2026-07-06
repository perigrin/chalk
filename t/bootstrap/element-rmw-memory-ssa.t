# ABOUTME: End-to-end memory-SSA: element read-modify-write ($a[0]++, $a[0]+=5, $h{k}++) stores back AND yields the right value.
# ABOUTME: The RMW-as-VALUE forms (post=old, pre=new, +=n=summed) are covered alongside read-after-store; lli == perl.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

skip_all "perl5-son not found"  unless -f "$SON/B/SoN.pm";
skip_all "lli not found"        unless -x $LLI;
skip_all "perl 5.42 not found"  unless -x $PERL;

use lib 'lib', 't/lib';
require Chalk::IR::Serialize::JSON;
require Chalk::Target::LLVM;

# Drive a snippet through B::SoN -> Chalk load -> LLVM lower -> lli.
sub lower_and_run ($body) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh "package main;\nsub corpus_case { $body }\n";
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return ('err', 'no JSON') unless $json =~ /\S/;
    my ($graphs, $mop) = Chalk::IR::Serialize::JSON::from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return ('err', 'no graph');
    my $ll = eval {
        Chalk::Target::LLVM->lower($g->returns->[0],
            (defined $mop ? (mop => $mop) : ()));
    };
    return ('gap', $@) if $@;
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    chomp $out;
    return ('value', $out);
}

# The perl oracle for the same body (as a scalar-context do-block).
sub perl_val ($body) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh "my \$r = do { $body }; print defined \$r ? \"Int:\$r\" : \"Undef:\";\n";
    close $fh;
    my $out = qx($PERL $tmp 2>&1);
    chomp $out;
    return $out;
}

# Each case: [body, expected]. expected computed here matches perl (asserted too).
my @cases = (
    # read-after-store: the store persists to the aggregate.
    ['$a[0]++; $a[0]'                 => 'Int:2',  'array'],
    ['$a[0]+=5; $a[0]'                => 'Int:6',  'array'],
    ['$a[0]-=2; $a[0]'                => 'Int:-1', 'array'],  # 1-2
    ['$h{k}++; $h{k}'                 => 'Int:2',  'hash'],
    # RMW-as-VALUE: post yields OLD, pre yields NEW, += yields the sum (ONCE).
    ['$a[0]++'                        => 'Int:1',  'array'],  # post -> old
    ['++$a[0]'                        => 'Int:2',  'array'],  # pre  -> new
    ['$a[0]+=5'                       => 'Int:6',  'array'],  # sum ONCE, not 11
    ['my $x=$a[0]++; $x'              => 'Int:1',  'array'],  # captured old
    ['$h{k}++'                        => 'Int:1',  'hash'],   # post -> old (k=1)
    # regressions that MUST stay correct:
    ['$a[0]=$a[0]+1; $a[0]'           => 'Int:2',  'array'],  # manual store-back
    ['$a[0]++; $a[1]'                 => 'Int:2',  'array'],  # sibling slot untouched
);

for my $c (@cases) {
    my ($body, $expect, $kind) = @$c;
    my $decl = $kind eq 'hash' ? 'my %h=(k=>1); ' : 'my @a=(1,2,3); ';
    my $full = "$decl$body";
    my $oracle = perl_val($full);
    is($oracle, $expect, "perl oracle [$full] == $expect") or next;
    my ($rk, $out) = lower_and_run($full);
    is("$rk:$out", "value:$expect", "lli [$full] -> $expect");
}

# Scalar RMW must stay correct (the fix must not touch the pad/targ path).
subtest 'scalar RMW unaffected' => sub {
    for my $c (['my $i=1; $i++; $i' => 'Int:2'],
               ['my $i=1; $i+=5; $i' => 'Int:6'],
               ['my $i=1; $i++'      => 'Int:1'],   # post -> old
               ['my $i=1; ++$i'      => 'Int:2']) { # pre  -> new
        my ($rk, $out) = lower_and_run($c->[0]);
        is("$rk:$out", "value:$c->[1]", "scalar [$c->[0]] -> $c->[1]");
    }
};

done_testing();
