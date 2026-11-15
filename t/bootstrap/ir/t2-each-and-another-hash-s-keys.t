# ABOUTME: each %h where the program takes keys or values of another named hash (which resets
# ABOUTME: that hash's iterator, not this one's) is T2's; of this hash, or of a deref, refused by name.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

# lower($src) -> (ll or undef, the .pl, why)
sub lower ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $pl, $err // $u->{path_why} // $u->{err});
}

for my $case (
    [ q{my %h = (a => 1, b => 2); my %one = (solo => 11); my $n = keys %h; my ($k, $v) = each %one; print "$n $k $v\n";},
      'keys of another my hash' ],
    [ q{%::g = (z => 10); my %one = (solo => 11); my $n = scalar(values %::g); my ($k, $v) = each %one; print "$n $k $v\n";},
      'values of a package hash' ],
) {
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

# KEYS OF THE SAME HASH, OR OF ONE THROUGH A REFERENCE (any hash): where it
# runs against the each is not known -- refused by name.
for my $case (
    [ q{my %one = (solo => 11); my ($k) = each %one; my $n = keys %one; my ($k2) = each %one; print "$k $n ", $k2 // 'u', "\n";}, 'keys of the same hash' ],
    [ q{my %one = (solo => 11); my $r = \%one; my $n = keys %$r; my ($k) = each %one; print "$n $k\n";}, 'keys through a reference' ],
) {
    my ($src, $name) = @$case;
    my ($ll, undef, $why) = lower($src);
    ok(!defined $ll, "$name: refused");
    like($why // '', qr/T2: out of its slices \(an each in a program with a keys or values/, "$name: by name") or diag $why;
}

done_testing;
