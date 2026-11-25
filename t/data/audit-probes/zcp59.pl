my @a=(1,2); my $w=sub { $a[0]=9 }; my @c=(@a,3); $w->(); print "@c\n";
