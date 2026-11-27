my $s = ""; my $i = 0; while (1) { $i++; next if $i == 2; last if $i > 3; $s .= $i } continue { $s .= "c" } print "$s\n";
