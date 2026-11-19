my @a = (1,2,3); my $s = shift(@a) . "-" . scalar(@a) . "-" . shift(@a); print "$s\n";
