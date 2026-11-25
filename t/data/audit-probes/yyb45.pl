my @a=(1,2); sub z { $a[1]=7 } my $s = join ",", map { z(); $_ } @a; print "$s\n";
