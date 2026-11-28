my $s = ""; my $i = 0; while ($i++ < 3) { eval { next if $i == 2; $s .= $i }; } print "$s\n";
