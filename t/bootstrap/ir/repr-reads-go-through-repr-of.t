# ABOUTME: Context.pm reads a value's representation through _repr_of, the one read
# ABOUTME: that honours a representation decided while lowering -- a ratchet on direct ->stamp reads.
use 5.42.0;
use utf8;
use Test::More;

# T1/T2 step 1 (plan-t1-t2): a representation decided once must be the one
# every consumer reads. `_repr_of` returns the per-lowering decision
# (cache 'repr:'), falling back to the node's stamp; a direct `->stamp`
# read ignores the decision. This counts the direct reads that remain.
#
# Not counted: set_stamp, comments, a line that builds a die or warn
# message, and a read marked `# static type` -- one that deliberately asks
# what the analysis said rather than how the value is held.
my $CEILING = 159;

open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
my ($n, @where) = (0);
my $in_repr_of;
while (my $line = <$fh>) {
    $in_repr_of = 1 if $line =~ /^sub _repr_of\b/;
    $in_repr_of = 0 if $in_repr_of && $line =~ /^}/;
    next if $in_repr_of;
    next if $line =~ /^\s*#/ || $line =~ /# static type/ || $line =~ /\b(?:die|warn)\b/;
    my $c = () = $line =~ /->stamp\b(?!_)/g;
    next unless $c;
    $n += $c;
    push @where, "$.: " . ( $line =~ s/^\s+//r ) =~ s/\n//r;
}
cmp_ok($n, '<=', $CEILING, "direct ->stamp reads in Context.pm: $n (ceiling $CEILING)")
    or diag join "\n", @where[ 0 .. ( $#where < 9 ? $#where : 9 ) ];

done_testing;
