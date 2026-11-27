my @a=(1,2); sub z { $a[1]=7 } print map { my $v=$_; z(); $v } @a; print "\n";
