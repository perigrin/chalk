my @a = (1,2,3); my $s = 0; { local $_; for (@a) { $s += $_ } } print "$s\n";
