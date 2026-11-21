# ABOUTME: A cell B::SoN makes on the control chain (wire v2: a MakeCell is a memory version
# ABOUTME: placed where it stands) is a statement T2 walks past: making a cell writes nothing.
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

# lower($src) -> (ll or undef, the .pl, why): through T2 alone
sub lower ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json,wire=2 $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $pl, $err // $u->{path_why} // $u->{err});
}

# as_perl([src, name], ...): each through T2 alone, its output, message and exit code perl's.
sub as_perl (@cases) {
    for my $case (@cases) {
        my ($src, $name) = @$case;
        my ($ll, $pl, $why) = lower($src);
        ok(defined $ll, "$name: lowered through T2") or diag $why;
        next unless defined $ll;
        my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $lf $ll; close $lf;
        my $got  = run("timeout 20 $LLI $llp");
        my $want = run("$^X $pl");
        is($got->[0], $want->[0], "$name: perl's output");
        is($got->[1], $want->[1], "$name: perl's message");
        is($got->[2], $want->[2], "$name: perl's exit code");
    }
}

# WHY. B::SoN made a MakeCell the memory version and left it off the
# control chain (wire v2's V2, version-off-chain); stage 4 pins it, as every
# other version is. T2 makes a cell where its value is first asked for (the
# variable's own storage, or for an aggregate a reference made at entry), so
# on the chain there is nothing to make: refused as "a statement MakeCell"
# before this, it is walked past.
as_perl(
    [ q{my $n = 1; my $f = sub { $n += 2; 1 }; $f->(); print "$n\n";}, 'a scalar cell, written by the closure' ],
    [ q{my $n = 1; my $f = sub { $n }; $n *= 3; print $f->(), "\n";}, 'a scalar cell, written by its maker' ],
    [ q{sub f { my @p = (5); my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); my $a = "@p"; @p = (); $c->(3); return "$a/@p" } print f(), "\n";}, 'an array cell' ],
    [ q{my $a = 1; my $b = 2; my $f = sub { $a + $b }; $a = 10; print $f->(), "\n";}, 'two cells, one after the other' ],
);
done_testing;
