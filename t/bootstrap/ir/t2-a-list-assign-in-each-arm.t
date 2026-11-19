# ABOUTME: a variable a list assignment in each arm of an if gives a value (B::SoN: one node, no merge)
# ABOUTME: reads after the join the value of the arm taken.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
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
    [ q~sub two { return ($_[0] * 2, 1) }
sub f { my ($lo, $n); if ($_[0] > 1) { ($lo, $n) = two($_[0]); $n += 1 } else { ($lo, $n) = (ord("a"), 5) } return "$lo $n" }
print f(3), " ", f(0), "\\n";
~, 'each arm list-assigns the variables, read after the join', q~~ ],
    [ q~sub f { my ($a, $b) = (1, 2); if ($_[0]) { ($a, $b) = (7, 8) } return "$a$b" }
print f(1), f(0), "\\n";
~, 'one arm list-assigns, the variable assigned before the if', q~~ ],
    [ q~sub esc { return (ord($_[0][$_[1]]) + 100, 1) }
sub f {
    my @chars = split //, $_[0];
    my @ranges; my $j = 0;
    while ($j <= $#chars) {
        my $cc = $chars[$j];
        last if $cc eq ']';
        my ($lo, $lo_used);
        if ($cc eq '\\\\') { ($lo, $lo_used) = esc(\\@chars, $j + 1); $lo_used += 1 }
        else { ($lo, $lo_used) = (ord($cc), 1) }
        my $k = $j + $lo_used;
        if (($chars[$k] // '') eq '-') { push @ranges, "$lo-" . ord($chars[$k + 1]); $j = $k + 2; next }
        push @ranges, $lo;
        $j = $k;
    }
    return "@ranges";
}
print f('a\\\\nb-d]'), "\\n";
~, 'in a loop, as a parser walks a string', q~~ ],
) {
    my ($src, $name, $refuse) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    if (length $refuse) {
        ok(!$err && ( $u->{path} // '' ) ne 't2' && ( $u->{path_why} // '' ) =~ /$refuse/, "$name: refused by name") or diag $err // $u->{path_why} // 'lowered';
        next;
    }
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    ok(defined $ll, "$name: lowered through T2") or diag $err // $u->{path_why} // $u->{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lf, ':utf8'; print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

done_testing;
