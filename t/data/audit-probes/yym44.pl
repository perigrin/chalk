my @a = (3,1,2); my @i = sort { $a[$a] <=> $a[$b] } 0..$#a; my @s = @a[@i]; my @r = (0) x @a; @r[@i] = 0..$#a; my ($first, @rest) = @s; my $last = pop @rest; print "@i|@s|@r|$first@rest$last\n";
