my @a=(1,2); sub z { $_++ for @a } for my $x (@a) { z(); print $x } print "\n";
