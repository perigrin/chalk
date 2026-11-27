my @a=(1,2); my @b=(3); sub z { $a[1]=7 } for my $x (@a,@b) { print $x; z() } print "\n";
