my @a = (1,2,3); my ($min) = sort { $a <=> $b } @a; my ($max) = sort { $b <=> $a } @a; print "$min$max@a\n";
