my @a=(1,2); my $s=0; my @c=@a; for my $i (0..1) { $a[$i]=9; $s+=$c[$i] } print "$s\n";
