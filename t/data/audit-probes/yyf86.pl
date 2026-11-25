my @q=(1,2,3); my $s=""; while (my $l = shift @q) { $s .= $l; push @q, 9 if $l == 1 } print "$s\n";
