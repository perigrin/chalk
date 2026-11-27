my @a=(1); my $e=\$a[0]; my $s = $a[0] . ($$e = 7); print "$s\n";
