my $n = 0; my @s = sort { $n++; $a <=> $b } (3, 1, 2); print $n > 0 ? "cmp" : "none", "@s\n";
