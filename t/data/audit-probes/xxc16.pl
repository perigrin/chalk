my @a=(3,1,2); my $c = 0; my @s = sort { $c += $a; $a <=> $b } @a; print $c > 0 ? 1 : 0, "\n";
