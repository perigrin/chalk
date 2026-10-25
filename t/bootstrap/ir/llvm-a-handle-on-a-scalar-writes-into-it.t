# ABOUTME: A handle opened for writing on a reference to a scalar appends what is printed or
# ABOUTME: said to it into the scalar: B::SoN -> chalk -> lli == perl.
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

# open(my $out, ">", \my $buf) WRITES INTO $buf (pvm 428, 430). It was
# refused ("open in a mode other than \"<\"").
for my $c (
    [ q{open(my $out, ">", \my $buf); print $out "captured\n"; close($out); print $buf;},                      "captured\n",      'print to it' ],
    [ q{use feature "say"; open(my $out, ">", \my $buf); say $out "a"; print $out "b"; close($out); print "[$buf]\n";}, "[a\nb]\n", 'say, then print' ],
    [ q{my $buf = "old"; open(my $out, ">", \$buf); print $out "new"; close($out); print "$buf\n";},              "new\n",           '">" empties it first' ],
    [ q{my $buf = "old"; open(my $out, ">>", \$buf); print $out "+"; close($out); print "$buf\n";},               "old+\n",          '">>" appends' ],
    [ q{open(my $out, ">", \my $buf); print $out "x"; print "[$buf]\n"; close($out);},                          "[x]\n",           'read before the close' ],
    [ q{open(my $out, ">", \my $buf); print STDOUT "o\n"; print $out "x"; close($out); print "$buf\n";},        "o\nx\n",          'STDOUT by name' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
