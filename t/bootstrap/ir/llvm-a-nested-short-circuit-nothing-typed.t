# ABOUTME: a short-circuit nothing typed, nested in another, is the Scalar its arms are:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused by name.
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

sub through_llvm ($src) {
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
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# `if ($c) { if ($a && $b) { ... } }` falling off its end returns the failed
# test: `$c && ($a && $b)`. The inner && was typed only once lowered, so the
# outer took it for Unknown and refused (pvm 174, "And.LHS[Scalar -> Unknown]").
for my $case (
    [ q{sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { return "y" } } }
        my @r = map { scalar(f(@$_)) // "u" } [1, "P", 3], [1, "P", 0], [0, 1, 1]; print "@r\n";}, "y 0 0\n", 'a nested && falls off, by flattened arguments' ],
    [ q{sub f { my ($c, $a, $b) = @_; $c && ($a || $b) } my @x = (1, 0, "z"); my @y = (0, 1, 1); print f(@x), "|", f(@y), "\n";}, "z|0\n", 'an && over an ||' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (!defined $got && $@ =~ /GAP/ && $@ !~ /Unknown\]/) { pass("$name: refused by name"); diag $@; next }
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
