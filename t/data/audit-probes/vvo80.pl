my @a = (1,2,3); my $s = ""; for my $e (@a[0,1] = (7, 8)) { $s .= $e; $a[1] = 0 } print "$s\n";
