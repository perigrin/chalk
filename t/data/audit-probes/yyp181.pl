my @a=("ab","c"); my @l = (@a, $a[0] =~ tr/a/z/); print "@l\n";
