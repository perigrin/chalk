# ABOUTME: the variable an in-memory handle writes, read where its memory version stands after the handle's
# ABOUTME: close on the control chain (statements and calls after it), holds what the prints wrote.
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
    [ q~open(my $out, ">", \\my $buf);
print $out "a";
print $out "b\\n";
close($out);
my $n = 2 * 3;
sub f { return "f$_[0]" }
my $s = f($n);
print "$s $buf";
~, 'the variable a handle wrote, read statements after its close', q~~ ],
    [ q~open(my $out, ">", \\my $buf);
my $prev = select($out);
print "round trip\\n";
select($prev);
close($out);
sub g { 7 }
print g(), " ", $buf;
~, 'written through select, read after the close and a call', q~~ ],
    [ q~open(my $out, ">", \\my $buf);
print $out "a";
my $copy = $buf;
print $out "b";
close($out);
print "[$copy] [$buf]\\n";
~, 'read between a print and the close', q~a variable a handle writes, read other than after a close~ ],
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
