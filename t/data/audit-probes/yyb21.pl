my ($s,$t)=(1,2); sub z { $s=7 } for my $x ($s,$t) { z(); print $x } print "\n";
