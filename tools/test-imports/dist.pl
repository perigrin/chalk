# dist.pl SUMMARY.tsv [filterfile] -- median/p90/max of the per-test totals
use v5.42;
my ($f, $only) = @ARGV;
my %keep; if ($only) { open my $k, '<', $only or die; chomp(my @l = <$k>); %keep = map { $_ => 1 } @l }
open my $fh, '<', $f or die; chomp(my $h = <$fh>); my @h = split /\t/, $h;
my %col; my %maxt;
while (<$fh>) { chomp; my @F = split /\t/, $_, -1; my %r; @r{@h} = @F; next if $only && !$keep{$r{test}};
  for my $k (@h[8..$#h]) { push $col{$k}->@*, $r{$k}; $maxt{$k} = $r{test} if !defined $maxt{"v$k"} || $r{$k} > $maxt{"v$k"}; $maxt{"v$k"} = $r{$k} if !defined $maxt{"v$k"} || $r{$k} > $maxt{"v$k"} } }
for my $k (@h[8..$#h]) { my @v = sort { $a <=> $b } $col{$k}->@*; my $s = 0; $s += $_ for @v;
  printf "%-22s n=%d  median=%-7d p90=%-7d max=%-7d (%s) mean=%.0f\n", $k, scalar @v, $v[int($#v/2)], $v[int(0.9*$#v)], $v[-1], $maxt{$k}, $s/@v }
