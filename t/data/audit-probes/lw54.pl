my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); next if $i > 5; for (@a) { $_ .= "x" } } print "@r\n";
