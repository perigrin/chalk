our @g=(1,2,3); sub z { $g[1] = 0 } for my $x (@g) { z(); print $x } print "\n";
