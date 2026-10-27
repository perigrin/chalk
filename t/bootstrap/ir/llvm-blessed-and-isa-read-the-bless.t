# ABOUTME: blessed($x) is the class bless recorded for a reference (undef for anything
# ABOUTME: else) and `$x isa C` asks whether it is C: B::SoN -> chalk -> lli == perl.
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

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
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


# blessed and isa had no lowering (pvm 180, 058).
for my $c (
    [ q{use Scalar::Util qw(blessed); package K { sub new { bless {}, shift } sub ok { 1 } } my @a = (K->new, 3, K->new); my @g = grep { blessed($_) } @a; print scalar(@g), "\n";} ],
    [ q{use v5.36; package Foo; package Bar; package main; my $o = bless {}, $ENV{X} // "Foo"; my $yes = $o isa Foo; my $no = $o isa Bar; print "$yes$no|\n";} ],
    [ q{use Scalar::Util qw(blessed); my $r = {}; my $b = bless [], "P"; print defined(blessed($r)) ? "d" : "u", blessed($b), defined(blessed(7)) ? "d" : "u", "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# INHERITANCE `use parent` SETS UP is in a use the loader drops: `$o isa A` for
# a B that inherits from A said "n" for perl's "y". Perl's answer, or refused.
{
    my $src = q{use v5.36; package A { } package B { use parent -norequire, "A"; } package main; my $o = bless {}, "B"; print $o isa A ? "y" : "n", "\n";};
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq "y\n" ) || $@ =~ /GAP/, "isa through use parent: perl's answer or refused")
        or diag "got: " . ( $got // "undef" ) . " $@";
}

done_testing;
