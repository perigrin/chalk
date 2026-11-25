my $x = my $y = 5; my ($a1, $b1) = (1); my ($c1, @r) = (1,2,3); my ($d1, $e1, @s) = (1); print "$x$y$a1", defined $b1 ? "d" : "u", "$c1@r", scalar(@s), "\n";
