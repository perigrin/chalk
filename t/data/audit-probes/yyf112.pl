my @st=(1); my $s=""; while (@st) { my $n = pop @st; $s .= $n; push @st, $n*2, $n*2+1 if $n < 4 } print "$s\n";
