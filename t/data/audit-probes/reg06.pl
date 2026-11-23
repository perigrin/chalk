my @a=(1,2); sub f { $_[0]=7; 0 } my @l=($a[0], f($a[0]), $a[0]); print "@l\n";
