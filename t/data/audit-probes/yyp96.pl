my @a=(1); my $e=\$a[0]; sub g { "@_" } print g($a[0], $$e = 7), "\n";
