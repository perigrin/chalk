# ABOUTME: delete $h{k} takes the key out of the hash and yields its value, or undef for a
# ABOUTME: key that is not there: B::SoN -> chalk -> lli == perl.
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

# delete was refused ("node op=Delete repr=Scalar", pvm 070 227 302 303).
for my $c (
    [ q{my %h = (a => 1, b => 2); my $gone = delete $h{a}; print $gone, " ", scalar(keys %h), " ", exists $h{a} ? "y" : "n", "\n";}, "1 1 n\n", 'a key there' ],
    [ q{my %h = (a => 1); my $g = delete $h{z}; print defined $g ? "d" : "u", " ", scalar(keys %h), "\n";},                        "u 1\n",   'a key not there' ],
    [ q{my %h = (a => 1, b => 2, c => 3); delete @h{"a", "b"}; print scalar(keys %h), " $h{c}\n";},                                "1 3\n",   'a slice of keys' ],
    [ q{my %h = (a => 1, b => 2, c => 3); delete $h{a}; $h{d} = 4; print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";},        "b=2,c=3,d=4\n", 'the rest kept, and added to' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
