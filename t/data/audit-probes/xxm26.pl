sub twice { $_[0] * 2 } my @r; for my $i (1..3) { my $x = $i; push @r, twice($x) } print "@r\n";
