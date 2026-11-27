my @a = (1,2,3); my $i = $#a; $#a = 0; my $j = $#a; $#a++; print "$i$j", scalar(@a), "\n";
