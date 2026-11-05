# ABOUTME: A read of what a loop or an if left, then a store to it: the read is made
# ABOUTME: after the merge, before the store -- not at its use (review family A).
our $LAST_LL;
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

sub through_llvm ($src, $env) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    $LAST_LL = $units->[0]{ll};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

for my $case (
    [ q{my $x = {n => 1}; for (1..2) { $x->{n}++ } my $t = $x->{n}; $x->{n} = 9; print "$t $x->{n}\n";}, q{p58} ],
    [ q{my %h = (n => 1); for (1..2) { $h{n}++ } my $t = $h{n}; $h{n} = 9; print "$t $h{n}\n";}, q{p59} ],
    [ q{my $x = {n => 1}; if (@ARGV) { $x->{n} = 2 } else { $x->{n} = 3 } my $t = $x->{n}; $x->{n} = 9; print "$t $x->{n}\n";}, q{p60} ],
    [ q{our %h = (a => 0); $h{a} += $_ for 1, 2; my $y = $h{a}; if (!@ARGV) { local $h{a} = 7; print "$h{a}\n" } print "$y $h{a}\n";}, q{q83} ],
    [ q{our $x = 0; sub f { local $x = 1; $x += $_ for 1, 2; my $y = $x; if (@ARGV) { $x = 9 } $y } print f(), " $x\n";}, q{q84} ],
    [ q{our $x = 0; if (@ARGV) { $x = 1 } else { $x = 2 } my $y = $x; if (!@ARGV) { $x = 5 } print "$y $x\n";}, q{q85} ],
    [ q{sub g { my ($h) = @_; $h->{n}++; 1 } my $x = {n => 1}; g($x) for 1..2; my $t = $x->{n}; g($x); print "$t $x->{n}\n";}, q{p55} ],
    [ q{sub g { my ($h) = @_; $h->{n}++; 1 } my $x = {n => 1}; my $i = 0; while ($i++ < 2) { g($x) } my $t = $x->{n}; g($x); print "$t $x->{n}\n";}, q{p57} ],
    [ q{my $h = {n => 1}; eval { for (1..2) { $h->{n}++ } my $t = $h->{n}; $h->{n} = 9; print "$t $h->{n}\n"; 1 };}, q{in an eval body: a hash reference} ],
    [ q{my %h = (n => 1); my $t = eval { $h{n}++ for 1..2; my $v = $h{n}; $h{n} = 9; $v }; print "$t $h{n}\n";}, q{in an eval body: a named hash, the value read after} ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { like($@, qr/GAP/, "$name: refused by name") }
}

done_testing;
