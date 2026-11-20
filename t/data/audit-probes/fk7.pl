my ($x, @r); my @a = (1); if (!@a) { ($x, @r) = (1, 2, 3) } print scalar(@r), "\n"; if (@a) { ($x, @r) = (4, 5, 6) } print "$x @r\n";
