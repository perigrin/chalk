my @a=(1,2); my $f=sub { $a[0]=9; 0 }; my $v = $a[0] + $f->() + $a[0]; print "$v\n";
