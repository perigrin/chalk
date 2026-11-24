my @a=(1,2); eval { my $i=0; while ($i<2) { $a[$i].="!"; $i++; die "x\n" } }; print "@a\n";
