# ABOUTME: A blessed reference knows its class: bless records it, ref() reads it back, and a
# ABOUTME: method call on it reaches its package's sub: B::SoN -> chalk -> lli == perl.
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

# BLESS NAMES A REFERENCE'S CLASS, and only ref() (and dispatch) can see
# it: the reference is the same pointer, its contents the same. chalk had
# no bless at all ("cannot lower op=Call builtin bless"), and ref() of a
# hash reference was the constant "HASH" -- which a blessed one is not.
for my $case (
    [ q{my $c = "Foo"; my $o = bless {}, $c; print ref $o, "\n";}, "Foo\n", 'a computed class (pvm 052)' ],
    [ q{my %a = (n => 1); my $c = "Foo"; my $o = bless { %a }, $c; print ref $o, " $o->{n}\n";}, "Foo 1\n", 'a copied hash (pvm 053)' ],
    [ q{package Foo; sub hi { return "hi" } package main; my $o = bless {}, "Foo"; print $o->hi, "\n";}, "hi\n", 'a method on a literal bless (pvm 054)' ],
    [ q{package Foo; sub new { bless { v => $_[1] }, $_[0] } sub v { $_[0]{v} } package main; my $o = Foo->new(3); print $o->v, " ", ref($o), "\n";}, "3 Foo\n", 'a constructor' ],
    [ q{my $h = {}; my $a = bless [1, 2], "Bar"; print ref($h), " ", ref($a), " ", scalar(@$a), "\n";}, "HASH Bar 2\n", 'an unblessed hash, a blessed array' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A REBLESSED REFERENCE: which class ref() reads would depend on where it is
# lowered, not where it stands. Refused by name.
{
    eval { through_llvm(q{my $o = bless {}, "A"; my $p = $o; bless $o, "B"; print ref($p), "\n";}) };
    like($@, qr/GAP: ref\(\) of a reference that a bless elsewhere changes/, 'a rebless is refused');
}

done_testing;
