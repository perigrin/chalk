# ABOUTME: A method called on an object whose class is known only at run time runs the sub
# ABOUTME: of the package its bless names: B::SoN -> chalk -> lli == perl.
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

# A method on an object of a run-time class was refused ("Call(method) X has
# no class_name", pvm 087 202 136).
for my $c (
    [ q{package N { sub new { bless { i => $_[1] }, $_[0] } sub id { $_[0]{i} } } package main; my @o = (N->new(1), N->new(2)); print join(",", map { $_->id } @o), "\n";} ],
    [ q{package A { sub new { bless {}, $_[0] } sub name { "a" } } package B { sub new { bless {}, $_[0] } sub name { "b" } } package main; my @o = (A->new, B->new, A->new); print join("", map { $_->name } @o), "\n";} ],
    [ q{package L { sub new { bless { n => $_[1] }, $_[0] } sub n { $_[0]{n} } } package main; my @s = sort { length($a->n) <=> length($b->n) } map { L->new($_) } qw(pear fig apple); print join(" ", map { $_->n } @s), "\n";} ],
    [ q{package P { sub new { bless { n => $_[1] }, $_[0] } sub n { $_[0]{n} } } package main; my @s = sort { $a->n cmp $b->n } map { P->new($_) } qw(pear apple fig); print join(" ", map { $_->n } @s), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A CLASS THE PROGRAM BLESSES INTO THAT LACKS THE METHOD is refused: perl
# dies there naming the file and line, which nothing here knows.
{
    eval { through_llvm(q{package A { sub new { bless {}, $_[0] } sub hi { "a" } } package C { sub new { bless {}, $_[0] } } package main; my @o = (A->new, C->new); print join(",", map { $_->hi } @o), "\n";}) };
    like($@, qr/GAP: .*does not have/, 'a blessed class without the method is refused');
}

done_testing;
