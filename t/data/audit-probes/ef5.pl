my $n = 0; my @s = sort { $n++; $a <=> $b } (3, 1, 2); my $m = $n; $n = 0; print(($m > 0 ? "y" : "n"), " $n @s\n");
