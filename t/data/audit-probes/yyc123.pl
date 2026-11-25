my @a=(1); my $r=\@a; my $n = ($r->[0] = 5) + ($a[0] = 7); print "$n\n";
