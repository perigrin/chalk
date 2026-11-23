my @a=(1,2); my $s=""; for my $x (@a) { $a[0] = "q"; $s .= $x } print "$s|@a\n";
