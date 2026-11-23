my @q=(1,2,3); my $f=sub { shift @q }; my $s=0; while (@q) { $s+=$f->() } print "$s\n";
