my $s = ""; my $i = 0; while ($i < 3) { $i++; next if $i == 2; $s .= $i } continue { $s .= "c" } print "$s\n";
