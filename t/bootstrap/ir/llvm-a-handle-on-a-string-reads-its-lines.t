# ABOUTME: A handle opened for reading on a reference to a string reads its lines -- one at
# ABOUTME: a time or all that are left -- and says eof at the end: B::SoN -> chalk -> lli == perl.
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

# open(my $fh, "<", \"...") READS THE STRING as a file (pvm 295-298). It was
# refused ("Call builtin open").
for my $c (
    [ q{open(my $fh, "<", \"x\n"); print "opened\n"; close($fh);},                           "opened\n",       'open and close' ],
    [ q{open(my $fh, "<", \"one\ntwo\n"); my $l = <$fh>; print $l; close($fh);},               "one\n",          'a line at a time' ],
    [ q{open(my $fh, "<", \"one\ntwo\n"); my @l = <$fh>; print scalar(@l), " $l[1]";},         "2 two\n",        'all the lines' ],
    [ q{open(my $fh, "<", \"a\nb"); my $x = <$fh>; my $y = <$fh>; my $z = <$fh>; print "$x|$y|", defined($z) ? "d" : "u", "\n";}, "a\n|b|u\n", 'the last line without a newline, then undef' ],
    [ q{open(my $fh, "<", \"only\n"); my $l = <$fh>; print "eof\n" if eof($fh); close($fh);}, "eof\n",          'eof at the end' ],
    [ q{open(my $fh, "<", \"a\nb\n"); my $l = <$fh>; print eof($fh) ? "yes" : "no", "\n";},    "no\n",           'not eof before it' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# EACH SUB'S HANDLE IS ITS OWN: two subs inlined into one function, each
# with a `my $fh`, do not share it.
{
    my $got = eval { through_llvm(q{sub inner { open(my $fh, "<", \"in\n"); my $l = <$fh>; return $l } sub outer { open(my $fh, "<", \"o1\no2\n"); my $a = <$fh>; my $i = inner(); my $b = <$fh>; return "$a$i$b" } print outer();}) };
    is($got, "o1\nin\no2\n", 'a callee\'s handle leaves its caller\'s alone') or diag $@;
}

# A REAL FILE is refused by name: only a string in memory is a file here.
{
    eval { through_llvm(q{open(my $fh, "<", "/etc/passwd"); my $l = <$fh>; print $l;}) };
    like($@, qr/GAP: open of a file/, 'a file on disk is refused');
}

done_testing;
