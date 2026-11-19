my $n = 0; sub cmpf { $n++; $a <=> $b } my @a = sort cmpf (3,1,2); print "@a ", ($n > 0 ? "y" : "n"), "\n";
