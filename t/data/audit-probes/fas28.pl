our $i=1; sub n { $i*=2 } my @l = ($i, n(), $i); print "@l\n";
