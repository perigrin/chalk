my $by = sub { $b <=> $a }; my @s = sort $by (3, 1, 2); print "@s\n";
