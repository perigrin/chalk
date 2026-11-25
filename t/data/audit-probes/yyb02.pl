my @a=(1,2); my $z = sub { $a[0]=7 }; for my $x (@a) { $z->(); print $x } print "\n";
