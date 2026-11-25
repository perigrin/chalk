my @a=(1); my $e=\$a[0]; my $n = ($a[0] = 5) + ($$e = 7); print "$n\n";
