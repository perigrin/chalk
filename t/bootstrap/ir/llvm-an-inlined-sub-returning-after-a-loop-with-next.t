# ABOUTME: An inlined sub whose value is read after a loop with a `next` in an arm
# ABOUTME: holding a loop of its own (pvm 205): the loop's exit merge dominates it.
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
    [ q{sub f { my @c = @_; my @o; my $i = 0;
  while ($i <= $#c) { my $x = $c[$i];
    if ($x eq 'b') { if ($c[$i+1] eq 'w') { $i += 2; next } my $j = $i + 1; while ($j <= $#c) { $j++ } $i = $j; next }
    if ($x eq '.') { $i++; next }
    push @o, $x; $i++ }
  return "@o" }
print f(qw(a b w . c b x y)), "|", f(qw(a . b x)), "\n";}, 'pvm 205' ],
    [ q{sub f { my @o; my $i = 0; while ($i < 4) { if ($i == 1) { my $j = $i + 1; while ($j < 4) { $j++ } $i = $j; next } push @o, $i; $i++ } return "@o" } print f(), "\n";}, 'pvm 205 shape: push, an inner loop, next' ],
    [ q{sub f { my @o; my $i = 0; while ($i < 6) { if ($i % 3 == 1) { my $j = $i; while ($j < $i + 2) { push @o, "j$j"; $j++ } $i = $j; next } push @o, $i; $i++ } return scalar(@o) . ":@o" } print f(), "\n";}, 'pvm 205 shape: the inner loop pushes' ],
    [ q{my $i = 0; my $s = 0; while ($i < 6) { if ($i == 1) { if ($s > 100) { $i += 2; next } my $j = $i; while ($j < 3) { $j++ } $i = $j; next } $s++; $i++ } print "$s $i\n";}, q{pvm 205 shape: two nexts in an arm, one after a loop} ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { fail("$name: perl's answer"); diag $@ }
}

done_testing;
