my @a=(1,2); sub w { $a[0]=9 } my $r=[@a]; w(); print "@$r\n";
