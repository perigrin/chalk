sub mk { my @a=(1,2); my $z=sub { $a[1]=7 }; my $s=""; for my $x (@a) { $z->(); $s.=$x } $s } print mk(), "\n";
