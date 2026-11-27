my @a=(1,2); my $f = sub { $a[1]=7 }; print map { my $v=$_; $f->(); $v } @a; print "\n";
