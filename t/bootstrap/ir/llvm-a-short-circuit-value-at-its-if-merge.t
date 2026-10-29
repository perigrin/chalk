# ABOUTME: an # ABOUTME: an arm that dies never reaches the merge, so its value is no phi entry:# ABOUTME: an arm that dies never reaches the merge, so its value is no phi entry: whose right side runs in an if arm is that if's merge, not a second short-circuit:
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

# `($c && $k->n) ? ... : ...` runs the call in an If's arm and reads the &&
# after the merge. Lowered as a second short-circuit there, it reused the
# call's value from the arm, which does not dominate it: lli, "Instruction
# does not dominate all uses".
for my $case (
    [ q{package K { sub new { bless { n => $_[1] }, $_[0] } sub n { $_[0]{n} } } my $k = K->new("x"); my $c = $ARGV[0] // 1; print(($c && $k->n) ? "t" : "f", "\n"); print $k->n, "\n";}, "t\nx\n", 'an && of a method, then the method again' ],
    [ q{package K { sub new { bless { n => $_[1] }, $_[0] } sub n { $_[0]{n} } } my $k = K->new("x"); my $e = K->new(""); my $c = $ARGV[0] // 1; print(($c && $k->n) ? "t" : "f", "\n"); print(($c && $e->n) ? "t" : "f", "\n");}, "t\nf\n", 'two &&s of one method on two objects' ],
    [ q{package K { sub new { bless { n => $_[1] }, $_[0] } sub n { $_[0]{n} } } my $k = K->new("x"); my $c = $ARGV[0] // 0; print(($c || $k->n), "\n");}, "x\n", 'an || of a method' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); diag $@; next }
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
