my @a=(1,2); sub z { $a[1]=7 } for (@a) { z(); print } print "\n";
