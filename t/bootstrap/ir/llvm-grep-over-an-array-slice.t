# ABOUTME: grep/map over an array slice or a computed range walk its elements: the count
# ABOUTME: and each element are read off the list made once: B::SoN -> chalk -> lli == perl.
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

# B::SoN walks `grep { } @a[...]` as Count(Slice) and Subscript(Slice, $i):
# a List had no length ("Length operand has repr=List", pvm 075 164 223).
for my $c (
    [ q{my @c = (1, 2, 3); my @x = grep { $_ > 1 } @c[0 .. 1]; print "@x\n";} ],
    [ q{my $c = [qw(a b c)]; print join("", grep { defined } @{$c}[1, 2, 5]), "\n";} ],
    [ q{my @c = (4, 5, 6); my @m = map { $_ * 2 } @c[2, 0]; print "@m\n";} ],
    # A range whose bound the program computes walks the same way (pvm 075).
    [ q{my $n = length("abc"); my @m = map { $_ * 2 } 1 .. $n; print "@m\n"; my @g = grep { $_ % 2 } 2 .. $n + 2; print "@g\n";} ],
    [ q{sub collect { my ($n) = @_; return () unless defined $n; my @c = map { "n$_" } 1 .. $n; return @c } my @a = collect(2); my @b = collect(0); print scalar(@a), " ", scalar(@b), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# perl's $_ is the array's own element: written through, it changes @a. The
# walk here is of a copy, so a write is refused rather than lost.
for my $src (q{my @a = (1, 2, 3); my @g = grep { $_ = 9 } @a[0, 1]; print "@a|@g\n";},
             q{my @a = (1, 2, 3); my @g = grep { $_++ } @a[0, 1]; print "@a|@g\n";}) {
    eval { through_llvm($src) };
    like($@, qr/perl aliases the array's element/, "a write through grep's \$_ is refused: $src");
}

done_testing;
