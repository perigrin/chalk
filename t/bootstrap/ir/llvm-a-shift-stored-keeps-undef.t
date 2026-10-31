# ABOUTME: `my $n = shift @a` of an Int array, which may be undef, is stored as a Scalar
# ABOUTME: that keeps it: B::SoN -> chalk -> lli == perl, or refused by name.
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






# An Int shift read by an Assign was refused: an empty array gives undef,
# which an Int holds as 0. Stored as its Slot, the variable keeps undef.
for my $case (
    [ q{my @w = (3, 4); my $s = ""; while (my $n = shift @w) { $s .= "[$n]" } print "$s\n";}, 'a while over a shift' ],
    [ q{my @w = (5); my $a = shift @w; my $b = shift @w; print defined $a ? "d" : "u", defined $b ? "d" : "u", " $a\n";}, 'a shift past the end is undef' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name: a plain variable (not kept in memory)
# rebinds to the Slot, and an untyped read of it took it for an Int -- "<><>"
# for perl's "<1><2>".
{
    my $src = q{sub g { "<$_[0]>" } sub f { my @w = (1, 2); my $s = ""; while (my $n = shift @w) { $s .= g($n) } $s } print f(), "\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass('pvm 151: refused by name') }
    else { is($got, perl_says($pl // write_pl($src), {}), "pvm 151: perl's answer") or diag $@ }
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
