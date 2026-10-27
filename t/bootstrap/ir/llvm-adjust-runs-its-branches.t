# ABOUTME: an ADJUST block with a branch or an op-assign on a field runs as perl runs it:
# ABOUTME: B::SoN -> chalk -> lli == perl.
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


# ADJUST bodies were lowered as a flat list of statements, so a store inside
# a branch (`//=`) was lost: 0 for perl's 5. `+=` gave invalid IR.
for my $src (
    q{use v5.42; use experimental "class"; class N { field $l :param = 3; ADJUST { $l += 5 } method l { $l } } print N->new->l, N->new(l => 1)->l, "\n";},
    q{use v5.42; use experimental "class"; class N { field $l :param = 3; ADJUST { $l += 5 } method l { $l } } print N->new->l, "\n";},
    q{use v5.42; use experimental "class"; class N { field $l :param = undef; ADJUST { $l //= 5 } method l { $l } } print N->new->l, N->new(l => 4)->l, "\n";},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A field with neither a default nor a :param starts undef. Typed by its
# ADJUST store it read as 0 there (perl: 5); now it is perl's answer or refused.
for my $src (
    q{use v5.42; use experimental "class"; class N { field $l; ADJUST { $l //= 5 } method l { $l } } print N->new->l, "\n";},
    q{use v5.42; use experimental "class"; class N { field $x :param; field $y; ADJUST { if ($x > 1) { $y = "big" } else { $y = "small" } } method y { $y } } print N->new(x => 2)->y, N->new(x => 0)->y, "\n";},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    ok(defined $got ? $got eq $want : $@ =~ /GAP/, "perl's answer or refused: $src") or diag $got // $@;
}

done_testing;
