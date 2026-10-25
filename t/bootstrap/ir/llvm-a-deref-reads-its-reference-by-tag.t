# ABOUTME: An array deref of a value read by its tag (a merge of a reference and its default)
# ABOUTME: derefs the reference it holds: B::SoN -> chalk -> lli == perl.
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

# `@{ $r->{s} // [] }`: the // merges a hash element (a Scalar) with an
# ArrayRef, so the merge is a Slot -- and the deref bitcast it as a pointer,
# which lli rejected (pvm 211, once its if over a parameter was lowered).
for my $case (
    [ q{sub f { my ($r, $e) = @_; my $o = ""; for my $s ($e ? @{ $r->{s} // [] } : ()) { $o .= $s } return $o } print f({s=>[1,2]}, 1), f({}, 1), f({s=>[3]}, 0), "\n";}, "12\n", 'a default for a missing element (pvm 211)' ],
    [ q{my %h = (a => [4, 5]); my $n = 0; for my $k (qw(a b)) { $n += scalar(@{ $h{$k} // [] }) } print "$n\n";}, "2\n", 'counted' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
