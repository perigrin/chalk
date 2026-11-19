my @a = (1); my $r = eval { $a[5]->{x}{y} = 1; scalar @a }; print "$r\n";
