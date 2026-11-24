my @a=(1,2); sub w { $a[0]=9 } sub cp { my @c=@a; return \@c } my $r=cp(); w(); print "@$r\n";
