# ABOUTME: a list assign to an array or hash field as a method's last statement: its value in
# ABOUTME: the caller's context -- the aggregate's list, or the count of the list assigned.
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

# lower($src) -> (ll or undef, the .pl, why)
sub lower ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $pl, $err // $u->{path_why} // $u->{err});
}

my $K = q{use v5.42; use experimental 'class';};
for my $case (
    [ qq{$K class K { field %h = (a => 1, b => 2); field \@l = (1, 2, 3);
        method reset_h { %h = () } method reset_l { \@l = (9) } method n { scalar(keys %h) . scalar(\@l) } }
        my \$k = K->new; my \$a = \$k->reset_h; my \@b = \$k->reset_l; print \$a, scalar(\@b), \$k->n, "\\n";},
      'a hash emptied, an array refilled: a count, a list' ],
    [ qq{$K class K { field \@l; method r { \@l = (7, 8, 9) } method n { scalar \@l } }
        my \$k = K->new; my \$c = \$k->r; my \@x = \$k->r; print "\$c \@x ", \$k->n, "\\n";},
      'an array refilled: the count assigned in a scalar, the array in a list' ],
    [ qq{$K class K { field %h; method set { %h = (a => 1) } }
        my \$k = K->new; my \$c = \$k->set; my \@p = \$k->set; print "\$c \@p\\n";},
      'a hash refilled: the count of the list in a scalar, its pairs in a list' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $pl, $why) = lower($src);
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

# ITS VALUE TAKEN OTHER THAN AS THE METHOD'S: refused by name.
{
    my ($ll, undef, $why) = lower(qq{$K class K { field \@l; method r { my \$n = (\@l = (1, 2)); \$n + 1 } } print K->new->r, "\\n";});
    ok(!defined $ll, 'its value taken in the method: refused');
    like($why // '', qr/T2: out of its slices \(/, 'refused by T2') or diag $why;
}

done_testing;
