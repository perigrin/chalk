# ABOUTME: In-memory handles through T2 alone: each op on an open, closed, never
# ABOUTME: opened or read-only handle answers as perl, or is refused by name.
use 5.42.0;
use Test::More;
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::T2Case;
use File::Temp qw(tempfile);

# perl's answer: the program from a file (__DATA__ is a file's).
sub perl_says ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return scalar qx($^X $pl 2>/dev/null);
}

# Each program's answer is perl's (T2 alone: a refusal fails here unless
# listed as one).
my @same = (
    # a print to a closed handle is false (it was true: [x][1])
    q{open(my $out, ">", \my $buf); print $out "x"; close($out); my $ok = print $out "y"; print "[$buf][", ($ok ? 1 : 0), "]\n";},
    # to an open one, true; to one open for reading, false
    q{open(my $out, ">", \my $buf); my $a = print $out "x"; open(my $in, "<", \"q\n"); my $b = print $in "z"; close($out); print "[$buf][", ($a ? 1 : 0), ($b ? 1 : 0), "]\n";},
    # a bare print to a selected handle closed under it: false, nothing written
    q{open(my $out, ">", \my $buf); my $prev = select($out); print "a"; close($out); my $ok = print "b"; select($prev); print "[$buf][", ($ok ? 1 : 0), "]\n";},
    # a read handle: readline past the end, after close, eof either way
    q{open(my $in, "<", \"a\nb"); my $x = <$in>; my $y = <$in>; my $z = <$in>; my $e = eof($in); close($in); my $w = <$in>; print "[$x][$y][", defined $z ? "d" : "u", "][$e][", defined $w ? "d" : "u", "][", (eof($in) ? 1 : 0), "]\n";},
    # readline and eof of a handle open for writing
    q{open(my $out, ">", \my $buf); my $l = <$out>; my $e = eof($out); close($out); print "[", defined $l ? "d" : "u", "][", ($e ? 1 : 0), "]\n";},
    # DATA: read, then closed
    qq{my \@l = <DATA>; close(DATA); my \$m = <DATA>; print scalar(\@l), defined \$m ? "d" : "u", "\\n";\n__DATA__\nx\ny\n},
);
for my $src (@same) {
    my $r = Chalk::CodeGen::Harness::T2Case::run_case({ src => $src, want => perl_says($src) });
    is($r->{verdict}, 'SAME', $src) or diag( $r->{why} // "got: $r->{got}" );
}

# Perl's answer, or refused by name -- never another answer.
for my $src (
    # close of a closed handle, and of one never opened (B::SoN places a
    # close whose value is read nowhere on the chain)
    q{open(my $in, "<", \"a"); my $c1 = close($in); my $c2 = close($in); my $fh; my $c3 = close($fh); print "[", ($c1 ? 1 : 0), ($c2 ? 1 : 0), ($c3 ? 1 : 0), "]\n";},
    # select of a `my $fh` never opened: a bare print goes nowhere
    q{my $fh; my $p = select($fh); my $ok = print "x"; select($p); print "after", ($ok ? 1 : 0), "\n";},
    # a print to a `my $fh` never opened: perl dies there
    q{my $fh; print "a\n"; print $fh "x"; print "after\n";},
    # a handle reopened while it is selected (perl's select holds the glob)
    q{open(my $out, ">", \my $b1); my $prev = select($out); open($out, ">", \my $b2); print "x"; select($prev); close($out); print "[$b1][$b2]\n";},
) {
    my $r = Chalk::CodeGen::Harness::T2Case::run_case({ src => $src, want => perl_says($src) });
    ok($r->{verdict} eq 'SAME' || $r->{verdict} eq 'REFUSED' && ( $r->{why} // '' ) =~ /out of its slices/, $src)
        or diag( $r->{why} // "got: $r->{got}" );
}

done_testing;
