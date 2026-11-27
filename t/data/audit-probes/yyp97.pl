my @a=(1); my $e=\$a[0]; my $n = $a[0] + $$e++; print "$n\n";
