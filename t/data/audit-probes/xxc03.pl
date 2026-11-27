my @a=(3,1,2); my $n = 0; my @s = sort { $n++; $a <=> $b } @a; print $n > 0 ? "c" : "z", "@s\n";
