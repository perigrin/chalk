our $x=1; sub n { $x=7; 1 } my @l=($x) x 2; n(); print "@l $x\n";
