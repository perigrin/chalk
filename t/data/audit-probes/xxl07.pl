our @q = (1,2,3); my $s = 0; while (defined(my $v = shift @q)) { $s += $v; push @q, 10 if $v == 1 } print "$s\n";
