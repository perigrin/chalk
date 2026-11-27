my @a=(1,2); sub z { $a[1]=7 } my @g = grep { my $v=$_; z(); $v > 1 } @a; print "@g\n";
