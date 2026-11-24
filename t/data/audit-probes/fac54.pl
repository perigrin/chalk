my @a=(1,2); my $n=0; for my $i (1..2) { my @b=@a; $b[0]+=$i; $n+=$b[0]; } print "$n @a\n";
