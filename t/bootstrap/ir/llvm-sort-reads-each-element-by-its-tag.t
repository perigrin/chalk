# ABOUTME: sort compares each element by its own reading: a string sort stringifies a
# ABOUTME: number as perl does, a numeric one numifies a string -- B::SoN -> chalk -> lli == perl.
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

# THE COMPARATOR READS EACH ELEMENT BY ITS TAG. A string sort over numbers
# was refused ("sort with a STRING comparator over a Array element", 11 pvm
# cases); over an Array operand it skipped that check and read each integer
# as a string pointer. A numeric sort compared raw payload bits: a negative
# Num sorts backwards as a bit pattern, and a Str as its pointer. Both now
# convert by the element's own tag -- Ints exactly, as perl's <=> does.
for my $case (
    [ q{print join(",", sort (10, 9, 100)), "\n";}, "10,100,9\n", 'a string sort of numbers' ],
    [ q{my @a = (3, -1.5, 2, -7); print join(",", sort { $a <=> $b } @a), "\n";}, "-7,-1.5,2,3\n", 'a numeric sort of negative Nums' ],
    [ q{my @a = ("10", "9", "100"); print join(",", sort { $a <=> $b } @a), "\n";}, "9,10,100\n", 'a numeric sort of strings' ],
    [ q{my @a = (2, 10, 1); print join(",", sort @a), "|", join(",", sort { $b cmp $a } @a), "\n";}, "1,10,2|2,10,1\n", 'a string sort of an array of Ints, both ways' ],
    [ q{my @a = (9007199254740993, 9007199254740992); print join(",", sort { $a <=> $b } @a), "\n";}, "9007199254740992,9007199254740993\n", 'Ints past 2**53 compared exactly' ],
    [ q{my @a = (2, "abc", 10); print join(",", sort @a), "\n";}, "10,2,abc\n", 'Ints and a Str' ],
    [ q{sub add { my ($h) = @_; $h->{b} = 2; 2 } sub f { my %pre = (a => 1); my $s = join(",", sort keys %pre); add(\%pre); return "$s|" . join(",", sort keys %pre) } print f(), "\n";}, "a|a,b\n", 'a sorted read taken before a call writes the hash (pvm)' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
