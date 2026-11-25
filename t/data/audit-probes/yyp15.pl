my @a=(1,2); my $f = sub { $a[1]=7 }; for (@a) { print $_; $f->() } print "\n";
