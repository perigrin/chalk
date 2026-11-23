my @a = (1,2); my @r; for my $i (1..2) { push @r, $a[0]; for (@a) { $_ .= "x" } } print "@r\n";
