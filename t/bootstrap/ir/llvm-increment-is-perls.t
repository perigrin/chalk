# ABOUTME: Perl's ++ on a value not proven a number: by its tag at run time, with the
# ABOUTME: magic string increment ("Az" -> "Ba") -- B::SoN -> chalk -> lli == perl.
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

# ++ ON A VALUE THAT MAY BE A STRING IS MAGIC, and B::SoN says so with an
# Increment node: `$h{a}++`, a counter a sub shares. chalk had no lowering
# for it, and the store of its result refused as "Assign with repr=Scalar"
# (11 pvm cases). The value's tag decides at run time: undef is 1, a number
# adds one, and a string of letters then digits counts in its own alphabet;
# any other string is its number plus one.
for my $case (
    [ q{my %h; my $a1 = $h{a}++; print "[$a1] $h{a}\n";}, "[0] 1\n", 'an absent element' ],
    [ q{my %h = (a => 0); $h{a}++; $h{a}++; print "$h{a}\n";}, "2\n", 'a number twice' ],
    [ q{my %h; my $b1 = ++$h{b}; my $b2 = ++$h{b}; print "$b1 $b2 $h{b}\n";}, "1 2 2\n", 'pre-increment' ],
    [ q{my $n = 0; sub f { $n++; return $n } f(); print f(), "\n";}, "2\n", 'a counter a sub shares' ],
    [ q{my %h = (k => "Az", z => "zz", n => "a9", d => "007", s => "3abc", e => "", f => "1.5", m => "-3", y => "Zz9", i => "inf"); for my $k (qw(d e f i k m n s y z)) { $h{$k}++; print "$k=$h{$k},"; } print "\n";},
      "d=008,e=1,f=2.5,i=ing,k=Ba,m=-2,n=b0,s=4,y=AAa0,z=aaa,\n", 'strings, magic and not' ],
    [ q{my %h = (x => 1.5); $h{x}++; print "$h{x}\n";}, "2.5\n", 'a Num' ],
    [ q{my $a = $ENV{X} // 5; my $b = $a++; my $c = ++$a; my $d = $a--; my $e = --$a; print "$a $b $c $d $e\n";}, "5 5 7 7 5\n", 'a defined string, up and down (pvm unary.md)' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
