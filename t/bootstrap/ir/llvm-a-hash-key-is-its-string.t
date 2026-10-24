# ABOUTME: A hash key is a string, whatever the key expression is: an element, a number,
# ABOUTME: a Scalar -- converted before the scan compares it. B::SoN -> chalk -> lli == perl.
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

# A KEY IS ITS STRING. The scan compares a key's bytes, so an array element
# (a Slot) or an Int handed to it as it was was taken apart as a %Str -- lli
# rejected the module (pvm chalk-found-gaps.md, `$seen{$x}++` over @_).
for my $case (
    [ q{sub count { my %seen; my $c = 0; for my $x (@_) { last if $x > 1 && $seen{$x}++; $c++ } return $c } print count(1, 2, 3, 2, 5), "\n";}, "3\n", 'an element of @_ as the key' ],
    [ q{my @a = (1, 2); my %h; $h{$a[0]} = "x"; print exists $h{$a[1]} ? "y" : "n", $h{1}, "\n";}, "nx\n", 'an array element as the key' ],
    [ q{my %h; my $k = 3; $h{$k} = "t"; $h{2.5} = "f"; print $h{3}, $h{"2.5"}, "\n";}, "tf\n", 'a number as the key' ],
    [ q{my $k = 7; my %h = ($k => "s"); print $h{7}, "\n";}, "s\n", 'a number as a literal key' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
