my @a = (1,2); my @r; my $i = 0; do { push @r, join(",", @a); for (@a) { $_ .= "x" } } while (++$i < 2); print "@r\n";
