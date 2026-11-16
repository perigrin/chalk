# ABOUTME: a reference to a constant (\1) is a SCALAR reference; what it holds is read-only, so a program
# ABOUTME: that dereferences a scalar is refused (a write through it dies in perl).
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
    [ q~use v5.42;
sub find ($n) {
    my $cur = $n;
    while (defined $cur) {
        if (ref $cur eq 'ARRAY') { return $cur->[0] eq 'x' ? 'found' : 'other' }
        if (ref $cur eq 'HASH') { $cur = $cur->{next}; next; }
        return 'stop';
    }
    return 'end';
}
print find({ next => { next => ['x'] } }), " ", find({ next => \\1 }), " ", find({ next => undef }), "\\n";
~, 'a constant reference walked to as a hash\'s value', q~~ ],
    [ q~my $r = \\"a";
print ref($r), " ", ($r ? "t" : "f"), " ", (defined $r ? "d" : "u"), "\\n";
~, 'its type and its truth', q~~ ],
    [ q~my $s = \\2; $$s = 5; print "$$s\\n";
~, 'a write through it, perl\'s die', q~a reference to a constant where the program dereferences a scalar~ ],
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
