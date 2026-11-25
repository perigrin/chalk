my @a = (1,2,3); my $s = join ",", map { $_ * 2 } grep { $_ % 2 } @a; my $t = join ",", sort { $b <=> $a } map { $_ + 1 } @a; my $u = join ",", reverse map { $_ } @a; print "$s|$t|$u\n";
