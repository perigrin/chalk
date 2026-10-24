# ABOUTME: uc, lc, ucfirst and lcfirst map ASCII letters as perl does, a number by its
# ABOUTME: string; a byte past ASCII is refused at run time -- B::SoN -> chalk -> lli == perl.
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

# CASE MAPPING (6 pvm cases refused "cannot lower op=Call builtin uc").
# ASCII is exact. A byte past ASCII is refused at run time (exit 255):
# whether perl maps it depends on character semantics this does not see.
for my $case (
    [ q{my $s = $ENV{S} // "aBc"; print uc($s), lc($s), ucfirst(lc $s), lcfirst($s), "\n";}, "ABCabcAbcaBc\n", 'the four' ],
    [ q{my $n = $ENV{N} // 42; print uc($n), ucfirst(""), lc("Hello, World 9!"), "\n";}, "42hello, world 9!\n", 'a number, an empty string, punctuation' ],
    [ q{sub shout { return uc $_[0] } my @loud = map { shout($_) } qw(a b c); print "@loud\n";}, "A B C\n", 'in a sub over map (pvm)' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

my $err = do { local $@; local $ENV{S} = "\xc3\xa9t"; eval { through_llvm(q{my $s = $ENV{S} // "x"; print uc($s), "\n";}) }; $@ };
like($err, qr/lli exited 255/, 'a byte past ASCII, read at run time, is refused there');

# A CONSTANT past ASCII is refused at compile time: chalk's strings are
# bytes, and its declared size counted the wrong unit (lli rejected it).
$err = do { local $@; eval { through_llvm(q{my $s = $ENV{S} // "\x{e9}t"; print length($s), "\n";}) }; $@ };
like($err, qr/GAP: a string constant with a character past ASCII/, 'a constant past ASCII is refused by name');

done_testing;
