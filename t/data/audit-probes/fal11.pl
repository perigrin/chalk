my @a=(1,2,3); my $r=\@a; my $t=0; for my $x (@a) { $t+=$x; $r->[2]=10 } print "$t\n";
