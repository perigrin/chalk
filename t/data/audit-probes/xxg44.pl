my @a = (1,2,3); my $s = join(",", @a, splice(@a, 0, 1), @a); print "$s\n";
