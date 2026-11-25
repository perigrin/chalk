my @a=(1,2); sub z { $a[1]=7 } my @g = map { my $v=$_; z(); $v } @a; print "@g\n";
