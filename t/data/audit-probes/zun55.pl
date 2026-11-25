our $g=1; my $i=0; while ($i++<2) { eval { local $g=7; die "x\n" }; } print "$g$i\n";
