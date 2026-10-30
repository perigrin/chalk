# ABOUTME: a reference passed to a Scalar argument read is read as the reference it is:
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

# `bless { i => $_[1] }, ...` of `N->new([7])`: the argument read is stamped
# Scalar and the caller's value an ArrayRef. lower_value boxed it to a %Slot
# while _repr_of said ArrayRef, so the hash literal took the Slot for a
# pointer (lli: "'%tmp' defined with type '%Slot'").
for my $case (
    [ q{package N { sub new { bless { i => $_[1] }, $_[0] } sub inputs { $_[0]{i} } }
        sub upd { my ($phi) = @_; my $inputs = $phi->inputs; return "none" unless defined $inputs && @$inputs; return "i=" . $inputs->[0] }
        print upd(N->new([7])), " ", upd(N->new([])), "\n";}, "i=7 none\n", 'an array reference stored by a constructor' ],
    [ q{sub f { my $h = { r => $_[0] }; return scalar @{ $h->{r} } } print f([1, 2, 3]), "\n";}, "3\n", 'an array reference stored in a hash literal' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); diag $@; next }
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
