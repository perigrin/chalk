my @a=(1,2,3); my $s=""; for my $i (0..$#a) { $s.=$i; push @a,0 if $i==0 } print "$s", scalar(@a), "\n";
