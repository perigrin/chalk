my @a=(1,2); my $r=\@a; print map { my $v=$_; $r->[1]=7; $v } @a; print "\n";
