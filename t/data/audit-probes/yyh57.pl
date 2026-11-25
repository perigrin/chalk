my @a = (1,2,3); my $n = grep { $_ > 1 } @a; my $m = map { ($_, $_) } @a; my ($g) = grep { $_ > 1 } @a; my $k = keys %{{ map { $_ => 1 } @a }}; print "$n$m$g$k\n";
