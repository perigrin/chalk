# ABOUTME: push of a reference (array, hash, scalar, code) appends it as one element, read
# ABOUTME: back as that reference: B::SoN -> chalk -> lli == perl.
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

# push took Int/Num/Str/Boolean and a value read by its tag; a reference was
# refused (pvm 194 198 219 230).
for my $c (
    [ q{my @r; push @r, [1, 2]; push @r, [3]; print scalar(@r), " ", scalar(@{ $r[0] }), " $r[1][0]\n";} ],
    [ q{my @r; push @r, { k => "v" }; print $r[0]{k}, "\n";} ],
    [ q{my $x = 5; my @r; push @r, \$x; ${ $r[0] } = 6; print "$x\n";} ],
    [ q{my @r; for my $i (1 .. 3) { push @r, [$i, $i * 2] } print join(",", map { $_->[1] } @r), "\n";} ],
    [ q{sub mk { my ($n) = @_; my @o; push @o, { n => $n }; $o[0]{n} } print mk(4), mk("x"), "\n";} ],
    # A named array in a list flattens: map over it reads each element by its
    # tag. Read as a nested array, lli rejected the module (older; Ints too).
    [ q{my @r; push @r, 5; push @r, 6; print join(",", map { $_ + 1 } @r), "\n";} ],
    [ q{my @r; push @r, [1, 2]; push @r, [3, 4]; my @s = map { $_->[0] } @r; print "@s\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
