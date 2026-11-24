my @a=(1,2); my $w=sub { $a[0]=9 }; my @c=@a; $w->(); print "@c\n";
