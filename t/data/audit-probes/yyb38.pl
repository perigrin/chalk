my @a=(1,2); sub z { $a[1]=7; "" } for my $x (@a) { print "$x" . z() . "$x" } print "\n";
