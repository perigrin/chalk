# ABOUTME: an argument nothing typed is passed as what it was lowered as:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused by name.
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

# `esc(\@chars, $j + 1)` in a loop: `$j + 1` is arithmetic nothing typed,
# lowered as an Int, but bound by its stamp (Unknown), so the callee's
# Scalar read of $_[1] refused (pvm 169, "an inlined argument is a Unknown
# where the callee reads a Scalar").
for my $case (
    [ q{sub esc { return (ord($_[0][$_[1]]) + 100, 1) }
        sub f { my @chars = split //, $_[0]; my $j = 0; my @r;
          while ($j <= $#chars) { my $cc = $chars[$j]; my ($lo, $u);
            if ($cc eq '\\\\') { ($lo, $u) = esc(\@chars, $j + 1); $u += 1 } else { ($lo, $u) = (ord($cc), 1) }
            push @r, $lo; $j += $u }
          return "@r" }
        print f('a\\\\nb'), "\n";}, "97 210 98\n", 'an index computed in a loop, passed' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# ARITHMETIC NOTHING TYPED, its operand typed only by its own lowering (an
# Add of an Add of a list-assigned target): read before lowering, the
# operand was Unknown and the Add refused (pvm 169). The program may still
# be refused further on -- by name, and not for this.
{
    my $got = eval { through_llvm(<<'PERL') };
sub esc { return (ord($_[0][$_[1]]) + 100, 1) }
sub f {
    my @chars = split //, $_[0];
    my @ranges; my $j = 0;
    while ($j <= $#chars) {
        my $cc = $chars[$j];
        last if $cc eq ']';
        my ($lo, $lo_used);
        if ($cc eq '\\') { ($lo, $lo_used) = esc(\@chars, $j + 1); $lo_used += 1 }
        else { ($lo, $lo_used) = (ord($cc), 1) }
        my $k = $j + $lo_used;
        if (($chars[$k] // '') eq '-') { push @ranges, "$lo-" . ord($chars[$k + 1]); $j = $k + 2; next }
        push @ranges, $lo;
        $j = $k;
    }
    return "@ranges";
}
print f('a\\nb-d]'), "\n";
PERL
    my $err = $@;
    ok(defined $got ? $got eq "97 210 98-100\n" : $err =~ /GAP/ && $err !~ /nothing typed over Unknown/,
       'pvm 169: not refused as arithmetic over an operand its lowering types') or diag $err;
}

# AN INDEX NOTHING TYPED is what its lowering made it: `$chars[$k]` with `$k`
# an Add nothing typed was read before it was lowered, so Unknown, and
# refused ("an array index with repr=Unknown", pvm 169).
{
    my $got = eval { through_llvm(<<'PERL') };
sub esc { return (ord($_[0][$_[1]]) + 100, 1) }
sub f { my @chars = split //, $_[0]; my $j = 0; my @r;
  while ($j <= $#chars) { my $cc = $chars[$j]; my ($lo, $lo_used);
    if ($cc eq 'x') { ($lo, $lo_used) = esc(\@chars, $j + 1); $lo_used += 1 } else { ($lo, $lo_used) = (ord($cc), 1) }
    my $k = $j + $lo_used;
    if (($chars[$k] // '') eq '-') { push @r, "$lo-" . ord($chars[$k + 1]); $j = $k + 2; next }
    push @r, $lo; $j = $k }
  return "@r" }
print f('a-bxyc'), "\n";
PERL
    is($got, "97-98 221 99\n", 'an index computed in a loop: perl\'s answer') or diag $@;
}

done_testing;
