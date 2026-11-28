my @a = (1,2,3); my $l; (@a, $l) = (@a, 9); print "@a|", defined $l ? "d" : "u", "\n";
