# ABOUTME: A glob is a value T2 knows by its name: read as a string it is *Pkg::name, a reference
# ABOUTME: to it is of type GLOB; what else a glob is (its slots, its address) is refused by name.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

sub t2 ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    return ( undef, $err ) if $err;
    my $u = $units->[0];
    return ( $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef, $u->{path_why} // $u->{err}, $pl );
}

for my $case (
    [ q{print ref(\*STDOUT), "\n";}, 'a reference to a glob is of type GLOB' ],
    [ q{package P; print *x, " ", *main::y, " ", *Q::z, " ", ref(\*x), "\n";}, 'a glob read as a string names its package' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $why, $pl) = t2($src);
    ok(defined $ll, "$name: lowered through T2") or diag $why;
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# WHAT A GLOB HOLDS (its slots) and where it is (its address) are the stash's,
# which T2 does not have yet: refused by name.
for my $src (q{my $g = \*STDOUT; print "$g" =~ /^GLOB/ ? "y" : "n", "\n";}, q{my $r = \*STDOUT; print {$r} "x\n";}) {
    my ($ll, $why) = t2($src);
    ok(!defined $ll, "not lowered: $src");
    like($why // '', qr/a glob|a reference to a glob|a print to a filehandle other than STDOUT/, "... refused by name: $src");
}

done_testing;
