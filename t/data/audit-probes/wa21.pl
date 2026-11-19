my @a = (1,2,3); my $x = $a[0] + $a[1]; ($a[0], $a[1]) = (10, 20) if @ARGV; $a[2] = $x; print "@a\n";
