my @a=(1,2); print map { my $v=$_; $a[1]=7; $v } @a; print "\n";
