my @q = (1,2,3); my $s = 0; while (my $x = shift @q) { $s += $x; push @q, 10 if $x == 1 } print "$s\n";
