our @a=(1,2); sub z { $a[1]=7 } for our $x (@a) { z(); print $x } print "\n";
