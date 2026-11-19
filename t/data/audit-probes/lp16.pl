my @a = (1,2,3,4); my @b; for my $x (@a) { next if $x == 2; last if $x == 4; push @b, $x } continue { push @b, "c" } print "@b\n";
