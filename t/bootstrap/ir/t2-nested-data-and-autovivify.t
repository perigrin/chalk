# ABOUTME: nested data (an element holding a reference) and autovivify: a deref for a write makes
# ABOUTME: the element (or the undef scalar) a new hash or array first; a read through undef is undef.
# (an element read WHOLE -- a print, a count, a foreach -- is refused: perl dies, reads undef or makes it.)
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

for my $case (
    [ q{my $r; $r->{a} = 1; print join(",", keys %$r), "\n";}, 'a hash element stored through an undef scalar' ],
    [ q{my $r; $r->[1] = 5; print scalar(@$r), "\n";}, 'an array element stored through an undef scalar' ],
    [ q{my $r = {}; $r->{a}{b} = 3; print $r->{a}{b}, "\n";}, 'a hash two levels down' ],
    [ q{my %h; $h{x}{y} = 6; print $h{x}{y}, "\n";}, 'a named hash two levels down' ],
    [ q{my @a = ([1, 2], [3]); print $a[0][1], $a[1][0], "\n";}, 'an array of arrays read' ],
    [ q{my %h; print defined($h{x}{y}) ? 1 : 0, "\n";}, 'a read through an undef element is undef' ],
    [ q{my @a; print defined($a[0][1]) ? 1 : 0, "\n";}, 'an array read through an undef element is undef' ],
) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $ll = !$err && $units->[0]{ok} ? $units->[0]{ll} : undef;
    ok(defined $ll && $ll =~ /^; chalk T2/m, "$name: lowered through T2") or diag $err // $units->[0]{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

done_testing;
