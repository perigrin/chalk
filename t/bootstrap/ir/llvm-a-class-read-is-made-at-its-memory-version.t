# ABOUTME: ref() and blessed() read a reference's class at the memory version B::SoN names
# ABOUTME: (their last input): before a bless when read before it. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

for my $case (
    # THE MEMORY A CLASS READ NAMES IS NOT A VALUE IT TAKES: a call also
    # printed as a list was "used both as a list and as a scalar" (RefType's
    # second input), a pinned `%{$r}` "a hash read whole taken as a scalar".
    [ q{sub f { (1, 2) } my $x = []; print f(); print ref($x), "\n";}, 'ref() after a call printed as a list' ],
    [ q{use Scalar::Util qw(blessed); sub f { (1, 2) } my $x = bless [], "K"; print f(); print blessed($x), "\n";}, 'blessed() after a call printed as a list' ],
    [ q{my $r = { a => 1 }; my %c = %{$r}; print ref($r), " ", scalar(keys %c), "\n";}, 'ref() after a hash copied through its reference' ],
    # READ BEFORE THE BLESS, PRINTED AFTER: the read is made at its version,
    # no later than the bless that replaces it.
    [ q{my $h = {}; my $r = ref($h); bless $h, "K"; print $r, " ", ref($h), "\n";}, 'ref() taken before a bless and printed after it' ],
    [ q{use Scalar::Util qw(blessed); my $h = {}; my $b = blessed($h); bless $h, "K"; print $b // "u", " ", blessed($h), "\n";}, 'blessed() taken before a bless and printed after it' ],
    [ q{my $h = {}; bless $h, "A"; my $r = ref($h); bless $h, "B"; print $r, " ", ref($h), "\n";}, 'ref() between two blesses' ],
    [ q{sub k { bless $_[0], "K"; return } my $h = {}; my $r = ref($h); k($h); print $r, " ", ref($h), "\n";}, 'ref() taken before a call that blesses' ],
    [ q{my @o = ({}, {}); for my $i (0 .. 1) { my $r = ref($o[$i]); bless $o[$i], "K$i"; print $r, " ", ref($o[$i]), "\n"; }}, 'ref() before a bless, in a loop' ],
    [ q{my $h = {}; my $r = $ARGV[0] ? "x" : ref($h); bless $h, "K"; print $r, " ", ref($h), "\n";}, 'ref() under a choice, before a bless' ],
) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $ll = !$err && $units->[0]{ok} ? $units->[0]{ll} : undef;
    ok(defined $ll && $ll =~ /^; chalk T2/m, "$name: lowered through T2") or diag $err // $units->[0]{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

done_testing;
