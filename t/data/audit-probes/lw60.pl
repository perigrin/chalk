my @a = (1,2); my @r; OUT: for my $i (1..3) { push @r, join(",", @a); for (@a) { $_ .= "x"; next OUT if $i == 2 } } print "@r\n";
