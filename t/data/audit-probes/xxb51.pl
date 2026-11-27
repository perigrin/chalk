my @a=(1,2,3); my $t = 0; $t += $_ for map { $_ * $_ } @a; print "$t\n";
