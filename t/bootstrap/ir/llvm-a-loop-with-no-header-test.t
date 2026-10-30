# ABOUTME: a loop with no header test (`while (1)`, left by `last` alone) runs until a
# ABOUTME: `last`: through B::SoN -> chalk -> lli == perl, or refused by name.
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


# `while (1)` has no header test -- perl folds it away -- and a body
# comparison on a loop variable was taken for one: `$s .= "a" if $x < 2`
# ended the loop at $x == 2 (perl's "f 5 aa" printed "f 2 aa").
for my $case (
    [ q{my $x = 0; my $s = ""; while (1) { $s .= "a" if $x < 2; $x = $x + 1; last if $s eq "aa" && $x > 4 } print "f $x $s\n";}, 'a body test on the loop variable is not the header' ],
    [ q{my $x = 0; while (1) { $x = $x + 1; last if $x == 3; } print "c $x\n";}, 'last at the end of the body' ],
    [ q{$x = 0; while (1) { $x = $x + 1; last if $x == 3; } print $x == 3 ? "ok 2\n" : "not ok 2\n"; $x = 0; while ($x != 3) { $x = $x + 1; } print "ok 3 $x\n";}, 'pvm 122' ],
    [ q{my $i = 0; my @o; while (1) { $i++; next if $i % 2; push @o, $i; last if $i >= 6 } print "@o\n";}, 'next and last' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); diag $@; next }
    is($got, perl_says($pl, {}), "$name: perl's answer") or diag $@;
}

done_testing;
