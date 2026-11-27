my @a=(1,2); sub z { $a[1]=7 } for (@a) { my $v=$_; z(); print $v } print "\n";
