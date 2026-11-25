my ($p, $q, $r) = (1, 2); my @a = (my $s = 5, my $t = 6); my $n = (($p, $q) = (7, 8, 9)); print "$p$q", defined $r ? "d" : "u", "@a$n\n";
