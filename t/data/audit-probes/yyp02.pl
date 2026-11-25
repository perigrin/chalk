my @a=(1,2); sub z { $a[1]=7 } for (@a) { print $_; z() } print "\n";
